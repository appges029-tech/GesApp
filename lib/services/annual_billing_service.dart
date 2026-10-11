import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../core/db/app_database.dart';
import '../core/session/business_write_guard.dart';
import '../core/session/operator_session.dart';
import 'school_billing_periods.dart';

/// Crée des échéanciers sans toucher aux écritures déjà existantes.
/// Appelé dans la transaction de l'inscription ou de la réinscription.
class AnnualBillingService {
  const AnnualBillingService();
  static const _uuid = Uuid();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _read(Object? value) => _day(DateTime.parse(value as String));
  static DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static bool _covers(Map<String, Object?> row, DateTime d) {
    final from = _read(row['valid_from']);
    final to = row['valid_to'] == null ? DateTime(9999) : _read(row['valid_to']);
    return !d.isBefore(from) && !d.isAfter(to);
  }
  static String _key(DateTime d) =>
      d.year.toString() + '-' + d.month.toString().padLeft(2, '0');

  Future<BillingReconciliationResult> createForEnrollment(
    DatabaseExecutor db, {
    required String studentId,
    required String schoolYearId,
    required String classroomId,
    required DateTime enrolledAt,
  }) async {
    final years = await db.query('school_years',
        where: 'id=?', whereArgs: [schoolYearId], limit: 1);
    if (years.isEmpty) throw StateError('Année scolaire introuvable.');
    final yearStart = _read(years.first['start_date']);
    final yearEnd = _read(years.first['end_date']);
    final admission = _max(_day(enrolledAt), yearStart);
    if (admission.isAfter(yearEnd)) {
      throw StateError('Inscription hors de l’année scolaire active.');
    }
    final classRows = await db.query('classrooms',
        columns: ['cycle_id', 'name'], where: 'id=?', whereArgs: [classroomId], limit: 1);
    if (classRows.isEmpty) throw StateError('Classe introuvable.');
    final cycleId = classRows.first['cycle_id'] as String;
    final classroomName = classRows.first['name'] as String? ?? '';
    final examSettings = await db.query('app_settings', columns: ['value'],
      where: 'key=?', whereArgs: ['billing_exam_class:$classroomId'], limit: 1);
    final isExamClass = examSettings.isNotEmpty
        ? examSettings.first['value'] == 'true'
        : SchoolBillingPeriods.isExamClass(classroomName);
    final studentRows = await db.query('students',
        columns: ['family_id'], where: 'id=?', whereArgs: [studentId], limit: 1);
    if (studentRows.isEmpty) throw StateError('Élève introuvable.');
    final familyId = studentRows.first['family_id'] as String?;
    final fees = await db.rawQuery('''
      SELECT DISTINCT f.id, f.name, f.periodicity FROM fee_categories f
      LEFT JOIN fee_grid g ON g.fee_id=f.id
        AND (g.classroom_id=? OR (g.classroom_id IS NULL AND g.cycle_id=?))
      WHERE f.active=1 AND g.id IS NOT NULL
      ORDER BY f.name
    ''', [classroomId, cycleId]);
    final monthlyDeadlines = await BillingCalendarRepository.readMonthlyDeadlines(
        db, schoolYearId);
    final warnings = <String>[];
    var created = 0, existing = 0;
    for (final fee in fees) {
      final feeId = fee['id'] as String;
      final feeName = fee['name'] as String;
      final periodicity = fee['periodicity'] as String;
      // Rubrique + tarif + inscription are sufficient. Calendars may only
      // customize deadlines; they no longer determine which debts exist.
      final rules = await db.query('billing_calendar_rules',
        where: 'school_year_id=? AND fee_id=? AND enabled=1',
        whereArgs: [schoolYearId, feeId], limit: 1);
      final rule = rules.isEmpty ? null : rules.first;
      final rangeStart = rule == null ? yearStart :
          _max(yearStart, _read(rule['start_date']));
      final rangeEnd = rule == null ? yearEnd :
          _min(yearEnd, _read(rule['end_date']));
      if (rangeStart.isAfter(rangeEnd)) {
        warnings.add('Période invalide : $feeName');
        continue;
      }
      final periods = SchoolBillingPeriods.forYear(
        schoolYearStart: yearStart,
        schoolYearEnd: yearEnd,
        periodicity: periodicity,
        isExamClass: isExamClass,
      );
      for (final period in periods) {
        final start = _max(rangeStart, period.start);
        final end = _min(rangeEnd, period.end);
        if (end.isBefore(start)) continue;
        final periodKey = period.key;
        if (end.isBefore(admission)) continue;
        if (rule?['admission_policy'] == 'next_period' &&
            admission.isAfter(start) && !admission.isAfter(end)) continue;
        final tariffDate = _max(start, admission);
        final grids = await db.rawQuery('''
          SELECT * FROM fee_grid WHERE fee_id=? AND
             (classroom_id=? OR (classroom_id IS NULL AND cycle_id=?))
          ORDER BY CASE WHEN classroom_id IS NOT NULL THEN 0 ELSE 1 END,
                   valid_from DESC
        ''', [feeId, classroomId, cycleId]);
        Map<String, Object?>? tariff;
        for (final grid in grids) {
          if (_covers(grid, tariffDate)) { tariff = grid; break; }
        }
        if (tariff == null) {
          warnings.add('Tarif manquant : $feeName / $periodKey');
          continue;
        }
        Map<String, Object?>? package;
        if (familyId != null) {
          final family = await db.query('packages',
              where: "type='family' AND active=1 AND family_id=? AND fee_id=?",
              whereArgs: [familyId, feeId], orderBy: 'valid_from DESC');
          for (final item in family) {
            if (_covers(item, tariffDate)) { package = item; break; }
          }
        }
        if (package == null) {
          final individual = await db.query('packages',
              where: "type='individual' AND active=1 AND student_id=? AND fee_id=?",
              whereArgs: [studentId, feeId], orderBy: 'valid_from DESC');
          for (final item in individual) {
            if (_covers(item, tariffDate)) { package = item; break; }
          }
        }
        final duplicate = await db.query('dues', columns: ['id'],
            where: 'student_id=? AND fee_id=? AND period_key=?',
            whereArgs: [studentId, feeId, periodKey], limit: 1);
        if (duplicate.isNotEmpty) { existing++; continue; }
        if (package != null && package['type'] == 'family') {
          final shared = await db.query('dues', columns: ['id'],
              where: 'package_id=? AND fee_id=? AND period_key=? AND school_year_id=?',
              whereArgs: [package['id'], feeId, periodKey, schoolYearId], limit: 1);
          if (shared.isNotEmpty) { existing++; continue; }
        }
        final amount = (package?['amount'] ?? tariff['amount']) as int;
        if (amount <= 0) {
          warnings.add('Montant invalide : $feeName / $periodKey');
          continue;
        }
        // By default payment becomes overdue only after the period ends.
        // Optional calendars may set specific deadlines without creating dues.
        DateTime deadline = end;
        final configured = periodicity == 'mensuelle'
            ? monthlyDeadlines[periodKey]
            : null;
        if (configured != null) {
          deadline = _min(end, _max(start, configured));
        } else if (rule != null) {
          final day = rule['due_day'] as int? ?? 1;
          final lastDay = DateTime(start.year, start.month + 1, 0).day;
          final scheduled = DateTime(start.year, start.month,
              day > lastDay ? lastDay : day);
          deadline = _min(end, _max(scheduled, admission));
        }
        final now = DateTime.now().toIso8601String();
        final rowId = await db.insert('dues', {
          'id': _uuid.v4(), 'student_id': studentId, 'family_id': familyId,
          'fee_id': feeId, 'package_id': package?['id'],
          'school_year_id': schoolYearId, 'billing_batch_id': null,
          'period_key': periodKey, 'amount_due': amount,
          'amount_paid': 0, 'due_date': deadline.toIso8601String(),
          'status': 'unpaid', 'created_at': now, 'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (rowId > 0) { created++; } else { existing++; }
      }
    }
    if (fees.isEmpty) warnings.add('Aucun tarif pour cette classe.');
    final state = warnings.isEmpty ? 'ready' : 'pending_configuration';
    final details = warnings.toSet().join(' ; ');
    final now = DateTime.now().toIso8601String();
    await db.insert('student_billing_state', {
      'student_id': studentId, 'school_year_id': schoolYearId,
      'status': state, 'details': details, 'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update('student_billing_state',
        {'status': state, 'details': details, 'updated_at': now},
        where: 'student_id=? AND school_year_id=?',
        whereArgs: [studentId, schoolYearId]);
    return BillingReconciliationResult(created, existing, state, details);
  }
}

class BillingReconciliationResult {
  const BillingReconciliationResult(
      this.created, this.existing, this.status, this.details);
  final int created, existing;
  final String status, details;
}


/// Calendrier facultatif pour personnaliser les dates limites.
/// Les obligations sont déduites automatiquement du tarif et de la rubrique.
class BillingCalendarRepository {
  BillingCalendarRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<BillingCalendarConfiguration> load() async {
    final db = _database.db;
    final years = await db.query('school_years',
        where: 'is_active=1', limit: 1);
    if (years.isEmpty) {
      throw StateError('Configurez d’abord une année scolaire active.');
    }
    final y = years.first;
    final yearId = y['id'] as String;
    final fees = await db.rawQuery('''
      SELECT f.id fee_id, f.name fee_name, f.periodicity,
        CASE WHEN EXISTS(SELECT 1 FROM app_settings a WHERE a.key=?)
          THEN 1 ELSE 0 END monthly_configured,
        r.id rule_id, r.start_date, r.end_date, r.due_day,
        r.admission_policy, r.grace_days, r.enabled
      FROM fee_categories f
      LEFT JOIN billing_calendar_rules r ON r.fee_id=f.id
        AND r.school_year_id=?
      WHERE f.active=1 ORDER BY f.name
    ''', ['billing_month_deadlines:' + yearId, yearId]);
    return BillingCalendarConfiguration(
      yearId, y['label'] as String,
      DateTime.parse(y['start_date'] as String),
      DateTime.parse(y['end_date'] as String), fees);
  }

  /// Dates limites facultatives. Une date absente n'empêche jamais
  /// la création automatique de la mensualité correspondante.
  static Future<Map<String, DateTime>> readMonthlyDeadlines(
      DatabaseExecutor db, String schoolYearId) async {
    final rows = await db.query('app_settings', columns: ['value'],
      where: 'key=?', whereArgs: ['billing_month_deadlines:$schoolYearId'],
      limit: 1);
    if (rows.isEmpty) return {};
    final decoded = jsonDecode(rows.single['value'] as String);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Calendrier mensuel corrompu.');
    }
    return decoded.map((key, value) =>
        MapEntry(key, DateTime.parse(value as String)));
  }

  Future<void> saveMonthlyDeadlines(Map<String, DateTime> dates) async {
    BusinessWriteGuard.ensureAllowed('billing.months.manage');
    final data = await load();
    if (dates.isEmpty) {
      throw StateError('Sélectionnez au moins un mois de paiement.');
    }
    final periodStart = DateTime(data.start.year, data.start.month);
    final periodEnd = DateTime(data.end.year, data.end.month);
    final ordered = <String, String>{};
    for (final entry in dates.entries) {
      if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(entry.key)) {
        throw StateError('Période mensuelle invalide.');
      }
      final parts = entry.key.split('-');
      final month = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      final date = DateTime(entry.value.year,entry.value.month,entry.value.day);
      if (month.isBefore(periodStart) || month.isAfter(periodEnd) ||
          date.year != month.year || date.month != month.month ||
          date.isBefore(DateTime(data.start.year,data.start.month,data.start.day)) ||
          date.isAfter(DateTime(data.end.year,data.end.month,data.end.day))) {
        throw StateError('Date limite hors du mois ou de l’année scolaire.');
      }
      ordered[entry.key] = date.toIso8601String();
    }
    final key = 'billing_month_deadlines:' + data.yearId;
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((tx) async {
      final old = await tx.query('app_settings', where:'key=?',
          whereArgs:[key], limit:1);
      await tx.insert('app_settings', {
        'key':key, 'value':jsonEncode(ordered), 'updated_at':now,
      },conflictAlgorithm:ConflictAlgorithm.replace);
      await tx.insert('audit_log', {
        'entity_type':'billing_calendar','entity_id':data.yearId,
        'action':old.isEmpty?'configure_months':'revise_months',
        'old_value':old.isEmpty?null:old.single['value'],
        'new_value':jsonEncode(ordered),
        'operator_name':OperatorSession.current,
        'operator_id':OperatorSession.userId,
        'operator_role':OperatorSession.role,
        'created_at':now,
      });
    });
    // L'enregistrement des dates actives complète les échéanciers encore
    // manquants. Les paiements et les lignes déjà présentes sont intacts.
    await completePending(includeReady: true);
  }

  Future<void> saveRule({
    required String feeId, required DateTime startDate,
    required DateTime endDate, required int dueDay,
    required String admissionPolicy, required int graceDays,
  }) async {
    BusinessWriteGuard.ensureAllowed('billing.calendar.manage');
    final data = await load();
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final start = day(startDate), end = day(endDate);
    if (start.isBefore(day(data.start)) || end.isAfter(day(data.end)) ||
        end.isBefore(start)) {
      throw StateError('La période facturable doit rester dans l’année scolaire.');
    }
    if (dueDay < 1 || dueDay > 31) {
      throw ArgumentError('Le jour de paiement doit être compris entre 1 et 31.');
    }
    if (graceDays < 0 || graceDays > 90) {
      throw ArgumentError('Le délai d’admission doit être de 0 à 90 jours.');
    }
    if (!const {'current_period','next_period'}.contains(admissionPolicy)) {
      throw ArgumentError('Règle d’admission invalide.');
    }
    if (!data.fees.any((fee) => fee['fee_id'] == feeId)) {
      throw StateError('Type de frais inexistant ou désactivé.');
    }
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((tx) async {
      final rows = await tx.query('billing_calendar_rules',
        columns: ['id'], where: 'school_year_id=? AND fee_id=?',
        whereArgs: [data.yearId, feeId], limit: 1);
      final values = <String, Object?> {
        'start_date': start.toIso8601String(),
        'end_date': end.toIso8601String(),
        'due_day': dueDay,
        'admission_policy': admissionPolicy,
        'grace_days': graceDays,
        'enabled': 1,
        'updated_at': now,
      };
      if (rows.isEmpty) {
        await tx.insert('billing_calendar_rules', {
          'id': _uuid.v4(), 'school_year_id': data.yearId,
          'fee_id': feeId, ...values, 'created_at': now,
        });
      } else {
        await tx.update('billing_calendar_rules', values,
          where: 'id=?', whereArgs: [rows.first['id']]);
      }
      await tx.insert('audit_log', {
        'entity_type': 'billing_rule', 'entity_id': feeId,
        'action': rows.isEmpty ? 'create' : 'update',
        'new_value': data.yearId + '/' + start.toIso8601String() +
            '/' + end.toIso8601String() + '/' + dueDay.toString() +
            '/' + admissionPolicy,
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
    await completePending(includeReady: true);
  }

  /// Analyse le nombre de dossiers sans calendrier fiable; ne modifie rien.
  Future<int> pendingEnrollmentCount() async {
    final data = await load();
    final rows = await _database.db.rawQuery('''
      SELECT COUNT(*) count FROM student_enrollments e
      LEFT JOIN student_billing_state b ON b.student_id=e.student_id
        AND b.school_year_id=e.school_year_id
      WHERE e.school_year_id=? AND e.status='active'
        AND (b.status IS NULL OR b.status='pending_configuration')
    ''', [data.yearId]);
    return (rows.first['count'] as int?) ?? 0;
  }

  /// Reprise contrôlée des inscriptions historiques ou incomplètes.
  /// Le gestionnaire confirme d'abord la simulation; les états 'needs_review'
  /// ne sont jamais traités automatiquement.
  Future<BillingRepairResult> completePending({bool includeReady = false}) async {
    BusinessWriteGuard.ensureAllowed('billing.calendar.repair');
    final data = await load();
    final rows = await _database.db.rawQuery('''
      SELECT e.student_id,e.school_year_id,e.classroom_id,e.effective_from
      FROM student_enrollments e
      LEFT JOIN student_billing_state b ON b.student_id=e.student_id
        AND b.school_year_id=e.school_year_id
      WHERE e.school_year_id=? AND e.status='active'
        AND (b.status IS NULL OR b.status='pending_configuration'
          ${includeReady ? "OR b.status='ready'" : ""})
      ORDER BY e.student_id
    ''', [data.yearId]);
    var created = 0, completed = 0, pending = 0;
    final failed = <String>[];
    for (final row in rows) {
      try {
        final result = await _database.db.transaction((tx) =>
            const AnnualBillingService().createForEnrollment(tx,
              studentId: row['student_id'] as String,
              schoolYearId: row['school_year_id'] as String,
              classroomId: row['classroom_id'] as String,
              enrolledAt: DateTime.parse(row['effective_from'] as String)));
        created += result.created;
        if (result.status == 'ready') { completed++; } else { pending++; }
      } catch (error) {
        failed.add((row['student_id'] as String) + ' : ' + error.toString());
      }
    }
    return BillingRepairResult(created, completed, pending, failed);
  }
}

class BillingCalendarConfiguration {
  const BillingCalendarConfiguration(
      this.yearId, this.label, this.start, this.end, this.fees);
  final String yearId, label;
  final DateTime start, end;
  final List<Map<String, Object?>> fees;
}

class BillingRepairResult {
  const BillingRepairResult(
      this.created, this.completed, this.pending, this.errors);
  final int created, completed, pending;
  final List<String> errors;
}
