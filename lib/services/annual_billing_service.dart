import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

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
        columns: ['cycle_id'], where: 'id=?', whereArgs: [classroomId], limit: 1);
    if (classRows.isEmpty) throw StateError('Classe introuvable.');
    final cycleId = classRows.first['cycle_id'] as String;
    final studentRows = await db.query('students',
        columns: ['family_id'], where: 'id=?', whereArgs: [studentId], limit: 1);
    if (studentRows.isEmpty) throw StateError('Élève introuvable.');
    final familyId = studentRows.first['family_id'] as String?;
    final fees = await db.rawQuery('''
      SELECT DISTINCT f.id, f.name, f.periodicity FROM fee_categories f
      LEFT JOIN fee_grid g ON g.fee_id=f.id
        AND (g.classroom_id=? OR (g.classroom_id IS NULL AND g.cycle_id=?))
      LEFT JOIN billing_calendar_rules r ON r.fee_id=f.id
        AND r.school_year_id=? AND r.enabled=1
      WHERE f.active=1 AND (g.id IS NOT NULL OR r.fee_id IS NOT NULL)
      ORDER BY f.name
    ''', [classroomId, cycleId, schoolYearId]);
    final warnings = <String>[];
    var created = 0, existing = 0;
    for (final fee in fees) {
      final feeId = fee['id'] as String;
      final feeName = fee['name'] as String;
      final periodicity = fee['periodicity'] as String;
      final rules = await db.query('billing_calendar_rules',
          where: 'school_year_id=? AND fee_id=? AND enabled=1',
          whereArgs: [schoolYearId, feeId], limit: 1);
      if (rules.isEmpty) {
        warnings.add('Calendrier manquant : $feeName');
        continue;
      }
      final rule = rules.first;
      final rangeStart = _max(yearStart, _read(rule['start_date']));
      final rangeEnd = _min(yearEnd, _read(rule['end_date']));
      if (rangeStart.isAfter(rangeEnd)) {
        warnings.add('Période invalide : $feeName');
        continue;
      }
      final starts = <DateTime>[];
      if (periodicity == 'mensuelle') {
        for (var d = DateTime(rangeStart.year, rangeStart.month);
            !d.isAfter(rangeEnd); d = DateTime(d.year, d.month + 1)) {
          starts.add(_max(d, rangeStart));
        }
      } else if (periodicity == 'trimestrielle') {
        for (var d = rangeStart; !d.isAfter(rangeEnd);
            d = DateTime(d.year, d.month + 3, 1)) {
          starts.add(d);
        }
      } else if (periodicity == 'annuelle' || periodicity == 'unique') {
        starts.add(rangeStart);
      } else {
        warnings.add('Périodicité inconnue : $feeName');
        continue;
      }
      for (var i = 0; i < starts.length; i++) {
        final start = starts[i];
        DateTime end;
        String periodKey;
        if (periodicity == 'mensuelle') {
          end = _min(rangeEnd, DateTime(start.year, start.month + 1, 0));
          periodKey = _key(start);
        } else if (periodicity == 'trimestrielle') {
          end = i + 1 < starts.length
              ? starts[i + 1].subtract(const Duration(days: 1)) : rangeEnd;
          periodKey = yearStart.year.toString() + '-T' + (i + 1).toString();
        } else {
          end = rangeEnd;
          periodKey = yearStart.year.toString() + '-' + periodicity;
        }
        if (end.isBefore(admission)) continue;
        if (rule['admission_policy'] == 'next_period' &&
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
        final dueDay = rule['due_day'] as int;
        final last = DateTime(start.year, start.month + 1, 0).day;
        final contractual = DateTime(start.year, start.month,
            dueDay > last ? last : dueDay);
        final grace = (rule['grace_days'] as int);
        final deadline = _min(yearEnd,
            _max(contractual, admission.add(Duration(days: grace))));
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
