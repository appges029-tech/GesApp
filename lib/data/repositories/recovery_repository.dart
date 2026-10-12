import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import '../models/recovery.dart';

class RecoveryRepository {
  RecoveryRepository(this._database);

  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<String?> _activeSchoolYearId() async {
    final rows = await _database.db.query('school_years', columns: ['id'], where: 'is_active=1', limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  Future<List<RecoveryCaseItem>> cases({
    String? search,
    String? schoolYearId,
    String? cycleId,
    String? classroomId,
  }) async {
    final yearId = schoolYearId ?? await _activeSchoolYearId();
    if (yearId == null) throw StateError('Aucune année scolaire active.');
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final conditions = <String>[
      "d.status!='paid'",
      'd.due_date IS NOT NULL',
      'd.due_date < ?',
    ];
    final args = <Object?>[startOfToday.toIso8601String()];
    if (cycleId != null) {
      conditions.add('c.cycle_id = ?');
      args.add(cycleId);
    }
    if (classroomId != null) {
      conditions.add('c.id = ?');
      args.add(classroomId);
    }
    if (yearId != null) {
      conditions.add('d.school_year_id=?');
      args.add(yearId);
    }
    final query = (search ?? '').trim().toLowerCase();
    if (query.isNotEmpty) {
      conditions.add('''(
        lower(s.first_name) LIKE ? OR lower(s.last_name) LIKE ? OR
        lower(s.registration_number) LIKE ? OR lower(COALESCE(fam.name,'')) LIKE ? OR
        lower(COALESCE(g.name,s.guardian_name,'')) LIKE ? OR
        lower(COALESCE(g.phone,s.guardian_phone,'')) LIKE ?
      )''');
      final pattern = '%$query%';
      args.addAll(List<Object?>.filled(6, pattern));
    }
    final rows = await _database.db.rawQuery('''
      SELECT d.id due_id,d.student_id,d.period_key,d.amount_due,d.amount_paid,d.due_date,
             s.first_name,s.last_name,s.registration_number,
             COALESCE(fam.name,'') family_name,
             c.name classroom_name,fc.name fee_name,
             COALESCE(g.name,s.guardian_name) guardian_name,
             COALESCE(g.phone,s.guardian_phone) guardian_phone,
             ra.created_at last_action_at,ra.next_follow_up_at,
             ra.promise_amount,ra.promise_date
      FROM dues d
      JOIN students s ON s.id=d.student_id
      JOIN fee_categories fc ON fc.id=d.fee_id
      LEFT JOIN families fam ON fam.id=d.family_id
      LEFT JOIN student_enrollments se ON se.student_id=d.student_id AND se.school_year_id=d.school_year_id
      LEFT JOIN classrooms c ON c.id=COALESCE(se.classroom_id,s.classroom_id)
      LEFT JOIN student_guardians g ON g.student_id=s.id AND g.is_primary=1
      LEFT JOIN recovery_actions ra ON ra.id=(
        SELECT r2.id FROM recovery_actions r2 WHERE r2.due_id=d.id ORDER BY r2.created_at DESC LIMIT 1
      )
      WHERE ${conditions.join(' AND ')}
      ORDER BY d.due_date ASC,(d.amount_due-d.amount_paid) DESC,s.last_name,s.first_name
    ''', args);
    return rows.map((row) {
      final dueDate = DateTime.parse(row['due_date'] as String);
      final familyNameRaw = (row['family_name'] as String?)?.trim();
      return RecoveryCaseItem(
        dueId: row['due_id'] as String,
        studentId: row['student_id'] as String,
        studentName: '${row['last_name']} ${row['first_name']}',
        classroomName: (row['classroom_name'] as String?) ?? '—',
        feeName: row['fee_name'] as String,
        periodKey: row['period_key'] as String,
        balance: (row['amount_due'] as int) - (row['amount_paid'] as int),
        dueDate: dueDate,
        daysLate: now.difference(dueDate).inDays,
        familyName: familyNameRaw == null || familyNameRaw.isEmpty ? null : familyNameRaw,
        guardianName: row['guardian_name'] as String?,
        guardianPhone: row['guardian_phone'] as String?,
        lastActionAt: row['last_action_at'] == null ? null : DateTime.parse(row['last_action_at'] as String),
        nextFollowUpAt: row['next_follow_up_at'] == null ? null : DateTime.parse(row['next_follow_up_at'] as String),
        promiseAmount: row['promise_amount'] as int?,
        promiseDate: row['promise_date'] == null ? null : DateTime.parse(row['promise_date'] as String),
      );
    }).toList();
  }

  Future<List<RecoveryActionItem>> history(String dueId) async {
    final rows = await _database.db.query('recovery_actions', where: 'due_id=?', whereArgs: [dueId], orderBy: 'created_at DESC');
    return rows.map((row) => RecoveryActionItem(
      id: row['id'] as String,
      dueId: row['due_id'] as String,
      actionType: row['action_type'] as String,
      channel: row['channel'] as String?,
      contactName: row['contact_name'] as String?,
      outcome: row['outcome'] as String?,
      promiseAmount: row['promise_amount'] as int?,
      promiseDate: row['promise_date'] == null ? null : DateTime.parse(row['promise_date'] as String),
      nextFollowUpAt: row['next_follow_up_at'] == null ? null : DateTime.parse(row['next_follow_up_at'] as String),
      note: row['note'] as String?,
      status: row['status'] as String? ?? 'open',
      createdAt: DateTime.parse(row['created_at'] as String),
    )).toList();
  }

  Future<void> addAction({
    required String dueId,
    required String actionType,
    String? channel,
    String? contactName,
    String? outcome,
    int? promiseAmount,
    DateTime? promiseDate,
    DateTime? nextFollowUpAt,
    String? note,
  }) async {
    BusinessWriteGuard.ensureAllowed('addAction');
    if (actionType.trim().isEmpty) throw ArgumentError('Type d’action obligatoire.');
    if (promiseAmount != null && promiseAmount <= 0) throw ArgumentError('Montant promis invalide.');
    final due = await _database.db.query('dues', columns: ['id','amount_due','amount_paid'], where: 'id=?', whereArgs: [dueId], limit: 1);
    if (due.isEmpty) throw StateError('Échéance introuvable.');
    final balance = (due.first['amount_due'] as int) - (due.first['amount_paid'] as int);
    if (promiseAmount != null && promiseAmount > balance) {
      throw StateError('La promesse ne peut pas dépasser le solde de l’échéance.');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('recovery_actions', {
        'id': id,
        'due_id': dueId,
        'action_type': actionType.trim(),
        'channel': channel?.trim(),
        'contact_name': contactName?.trim(),
        'outcome': outcome?.trim(),
        'promise_amount': promiseAmount,
        'promise_date': promiseDate?.toIso8601String(),
        'next_follow_up_at': nextFollowUpAt?.toIso8601String(),
        'note': note?.trim(),
        'status': 'open',
        'operator_id': OperatorSession.userId,
        'created_at': now,
      });
      await txn.insert('audit_log', {
        'entity_type': 'recovery_action',
        'entity_id': id,
        'action': actionType.trim(),
        'new_value': 'due=$dueId; channel=${channel ?? ''}; outcome=${outcome ?? ''}; promise=${promiseAmount ?? 0}; next=${nextFollowUpAt?.toIso8601String() ?? ''}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<void> closeAction(String id) async {
    BusinessWriteGuard.ensureAllowed('closeAction');
    await _database.db.update('recovery_actions', {'status': 'closed'}, where: 'id=?', whereArgs: [id]);
  }

  Future<List<RecoveryActionItem>> dueFollowUps({int daysAhead = 7}) async {
    final now = DateTime.now();
    final end = now.add(Duration(days: daysAhead));
    final rows = await _database.db.query(
      'recovery_actions',
      where: "status='open' AND next_follow_up_at IS NOT NULL AND next_follow_up_at<=?",
      whereArgs: [end.toIso8601String()],
      orderBy: 'next_follow_up_at ASC',
    );
    return rows.map((row) => RecoveryActionItem(
      id: row['id'] as String,
      dueId: row['due_id'] as String,
      actionType: row['action_type'] as String,
      channel: row['channel'] as String?,
      contactName: row['contact_name'] as String?,
      outcome: row['outcome'] as String?,
      promiseAmount: row['promise_amount'] as int?,
      promiseDate: row['promise_date'] == null ? null : DateTime.parse(row['promise_date'] as String),
      nextFollowUpAt: row['next_follow_up_at'] == null ? null : DateTime.parse(row['next_follow_up_at'] as String),
      note: row['note'] as String?,
      status: row['status'] as String? ?? 'open',
      createdAt: DateTime.parse(row['created_at'] as String),
    )).toList();
  }
}
