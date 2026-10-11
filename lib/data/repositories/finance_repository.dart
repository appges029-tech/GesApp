import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../services/annual_billing_service.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import 'cash_rules.dart';
import '../models/finance.dart';
import '../models/finance_full.dart';

class FinanceRepository {
  FinanceRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<String?> _activeSchoolYearId(DatabaseExecutor db) async {
    final rows = await db.query(
      'school_years',
      columns: ['id'],
      where: 'is_active = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  Future<Map<String, Object?>?> _schoolYearForDate(
    DatabaseExecutor db,
    DateTime value,
  ) async {
    final iso = value.toIso8601String();
    final rows = await db.query(
      'school_years',
      where: 'start_date <= ? AND end_date >= ?',
      whereArgs: [iso, iso],
      orderBy: 'start_date DESC',
      limit: 1,
    );
    // Ne jamais substituer une autre année scolaire : facturation erronée.
    return rows.isEmpty ? null : rows.first;
  }

  /// Creates only the missing obligations for an already enrolled student.
  /// Idempotent: existing debts, allocations and receipts are never updated.
  Future<int> ensureAutomaticDuesForStudent(String studentId) async {
    BusinessWriteGuard.ensureAllowed('billing.ensure_for_student');
    final db = _database.db;
    final yearId = await _activeSchoolYearId(db);
    if (yearId == null) return 0;
    final enrollments = await db.query('student_enrollments',
      columns: ['student_id', 'school_year_id', 'classroom_id', 'effective_from'],
      where: "student_id=? AND school_year_id=? AND status='active'",
      whereArgs: [studentId, yearId], limit: 1);
    if (enrollments.isEmpty) return 0;
    final e = enrollments.first;
    final result = await db.transaction((tx) =>
      const AnnualBillingService().createForEnrollment(
        tx, studentId: studentId,
        schoolYearId: yearId,
        classroomId: e['classroom_id'] as String,
        enrolledAt: DateTime.parse(e['effective_from'] as String),
      ));
    return result.created;
  }

  Future<int> ensureAutomaticDuesForFamily(String familyId) async {
    BusinessWriteGuard.ensureAllowed('billing.ensure_for_family');
    final db = _database.db;
    final yearId = await _activeSchoolYearId(db);
    if (yearId == null) return 0;
    final members = await db.rawQuery('''
      SELECT DISTINCT e.student_id
      FROM student_enrollments e JOIN students s ON s.id=e.student_id
      WHERE s.family_id=? AND e.school_year_id=? AND e.status='active'
    ''', [familyId, yearId]);
    var created = 0;
    for (final member in members) {
      created += await ensureAutomaticDuesForStudent(member['student_id'] as String);
    }
    return created;
  }

  // --- Rubriques et grille tarifaire ------------------------------------

  Future<List<FeeCategoryItem>> feeCategories() async {
    final rows = await _database.db.query('fee_categories', where: 'active = 1', orderBy: 'name');
    return rows.map((r) => FeeCategoryItem(id: r['id'] as String, name: r['name'] as String, periodicity: r['periodicity'] as String)).toList();
  }

  Future<void> addFeeCategory({required String name, required String periodicity}) async {
    _requireDirector();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom de la rubrique est obligatoire.');
    const allowed = {'mensuelle', 'trimestrielle', 'annuelle', 'unique'};
    if (!allowed.contains(periodicity)) {
      throw ArgumentError.value(periodicity, 'periodicity', 'Périodicité non autorisée');
    }
    final existing = firstIntValue(await _database.db.rawQuery(
          'SELECT COUNT(*) FROM fee_categories WHERE lower(name) = lower(?) AND active = 1',
          [trimmed],
        )) ??
        0;
    if (existing > 0) throw StateError('Une rubrique active porte déjà ce nom.');

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('fee_categories', {
        'id': id,
        'name': trimmed,
        'periodicity': periodicity,
        'active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('audit_log', {
        'entity_type': 'fee_category',
        'entity_id': id,
        'action': 'create',
        'new_value': '$trimmed/$periodicity',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<void> updateFeeCategory({required String feeId,required String name,required String periodicity,bool active=true}) async {
    _requireDirector();final trimmed=name.trim();if(trimmed.isEmpty)throw ArgumentError('Le nom est obligatoire.');
    if(!const {'mensuelle','trimestrielle','annuelle','unique'}.contains(periodicity))throw ArgumentError('Périodicité invalide.');
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows=await txn.query('fee_categories',where:'id=?',whereArgs:[feeId],limit:1);if(rows.isEmpty)throw StateError('Rubrique introuvable.');
      if (rows.first['periodicity'] != periodicity) {
        final linked = firstIntValue(await txn.rawQuery(
          'SELECT COUNT(*) FROM dues WHERE fee_id=?', [feeId])) ?? 0;
        if (linked > 0) {
          throw StateError('Cette rubrique possède déjà des paiements ou obligations. '
            'Pour changer sa périodicité, créez une nouvelle rubrique '
            'afin de préserver l’historique.');
        }
      }
      final duplicate=firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM fee_categories WHERE lower(name)=lower(?) AND id<>? AND active=1',[trimmed,feeId]))??0;if(duplicate>0)throw StateError('Une autre rubrique active porte déjà ce nom.');
      await txn.update('fee_categories',{'name':trimmed,'periodicity':periodicity,'active':active?1:0,'updated_at':now},where:'id=?',whereArgs:[feeId]);
      await txn.insert('audit_log',{'entity_type':'fee_category','entity_id':feeId,'action':'update','old_value':'${rows.first['name']}/${rows.first['periodicity']}/${rows.first['active']}','new_value':'$trimmed/$periodicity/${active?1:0}','operator_name':OperatorSession.current,'operator_id':OperatorSession.userId,'operator_role':OperatorSession.role,'created_at':now});
    });
  }

  Future<void> deactivateFeeCategory(String feeId) async {
    _requireDirector();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('fee_categories', where: 'id = ?', whereArgs: [feeId], limit: 1);
      if (rows.isEmpty) throw StateError('Rubrique introuvable.');
      await txn.update(
        'fee_categories',
        {'active': 0, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [feeId],
      );
      await txn.insert('audit_log', {
        'entity_type': 'fee_category',
        'entity_id': feeId,
        'action': 'deactivate',
        'old_value': '${rows.first['name']}/${rows.first['periodicity']}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<void> addFeeGrid({required String feeId, String? cycleId, String? classroomId, required int amount, DateTime? validFrom}) async {
    _requireDirector();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Le montant doit être positif');
    if ((cycleId == null) == (classroomId == null)) {
      throw ArgumentError('Sélectionnez exactement un cycle ou une classe.');
    }
    final feeExists = firstIntValue(await _database.db.rawQuery(
          'SELECT COUNT(*) FROM fee_categories WHERE id = ? AND active = 1',
          [feeId],
        )) ??
        0;
    if (feeExists == 0) throw StateError('Rubrique introuvable ou désactivée.');
    if (classroomId != null) {
      final targetExists = firstIntValue(await _database.db.rawQuery(
            'SELECT COUNT(*) FROM classrooms WHERE id = ? AND active = 1',
            [classroomId],
          )) ??
          0;
      if (targetExists == 0) throw StateError('Classe introuvable ou désactivée.');
    } else {
      final targetExists = firstIntValue(await _database.db.rawQuery(
            'SELECT COUNT(*) FROM cycles WHERE id = ? AND active = 1',
            [cycleId],
          )) ??
          0;
      if (targetExists == 0) throw StateError('Cycle introuvable ou désactivé.');
    }
    final now = DateTime.now();
    final effective = validFrom ?? now;
    await _database.db.transaction((txn) async {
      final closeAt = effective.subtract(const Duration(microseconds: 1)).toIso8601String();
      if (classroomId != null) {
        await txn.update(
          'fee_grid',
          {'valid_to': closeAt},
          where: 'fee_id = ? AND classroom_id = ? AND valid_to IS NULL',
          whereArgs: [feeId, classroomId],
        );
      } else {
        await txn.update(
          'fee_grid',
          {'valid_to': closeAt},
          where: 'fee_id = ? AND classroom_id IS NULL AND cycle_id = ? AND valid_to IS NULL',
          whereArgs: [feeId, cycleId],
        );
      }
      final id = _uuid.v4();
      await txn.insert('fee_grid', {
        'id': id,
        'fee_id': feeId,
        'cycle_id': cycleId,
        'classroom_id': classroomId,
        'amount': amount,
        'valid_from': effective.toIso8601String(),
        'created_at': now.toIso8601String(),
      });
      await txn.insert('audit_log', {
        'entity_type': 'fee_grid',
        'entity_id': id,
        'action': 'create',
        'new_value': '$feeId/$cycleId/$classroomId/$amount/${effective.toIso8601String()}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now.toIso8601String(),
      });
    });
    // Une fois le tarif enregistré, toutes les inscriptions actives dont
    // le calendrier est prêt reçoivent leurs échéances manquantes. Les
    // anciennes lignes et tous les paiements sont préservés.
    final activeYear = await _activeSchoolYearId(_database.db);
    if (activeYear != null) {
      await BillingCalendarRepository(_database)
          .completePending(includeReady: true);
    }
  }

  Future<List<FeeGridItem>> feeGrid() async {
    final rows = await _database.db.rawQuery('''
      SELECT g.id, g.amount, g.valid_from, f.name fee_name,
             COALESCE(cl.name, c.name, 'Toutes classes') target_name
      FROM fee_grid g
      JOIN fee_categories f ON f.id = g.fee_id
      LEFT JOIN cycles c ON c.id = g.cycle_id
      LEFT JOIN classrooms cl ON cl.id = g.classroom_id
      WHERE g.valid_to IS NULL
      ORDER BY f.name, target_name
    ''');
    return rows
        .map((r) => FeeGridItem(
              id: r['id'] as String,
              feeName: r['fee_name'] as String,
              targetName: r['target_name'] as String,
              amount: r['amount'] as int,
              validFrom: DateTime.parse(r['valid_from'] as String),
            ))
        .toList();
  }

  Future<List<Map<String,Object?>>> feeGridHistory() => _database.db.rawQuery('''
    SELECT g.id,g.amount,g.valid_from,g.valid_to,f.name fee_name,COALESCE(cl.name,c.name,'Toutes classes') target_name
    FROM fee_grid g JOIN fee_categories f ON f.id=g.fee_id LEFT JOIN cycles c ON c.id=g.cycle_id LEFT JOIN classrooms cl ON cl.id=g.classroom_id
    ORDER BY f.name,target_name,g.valid_from DESC
  ''');

  // --- Génération des échéances ------------------------------------------

  Future<DueGenerationPreview> previewDues({
    required String periodKey,
    required String periodicity,
    required DateTime dueDate,
    DateTime? referenceDate,
  }) async {
    final db = _database.db;
    final effectiveDate = referenceDate ?? dueDate;
    if (dueDate.isBefore(effectiveDate)) {
      throw StateError('La date limite ne peut pas précéder la période facturée.');
    }
    final schoolYear = await _schoolYearForDate(db, effectiveDate);
    if (schoolYear == null) {
      throw StateError('Créez et activez une année scolaire avant de simuler les échéances.');
    }
    final schoolYearId = schoolYear['id'] as String;
    final managed = await db.query('billing_calendar_rules', columns:['id'],
        where:'school_year_id=? AND enabled=1', whereArgs:[schoolYearId], limit:1);
    final monthlyDates = await db.query('app_settings', columns:['key'],
        where:'key=?',whereArgs:['billing_month_deadlines:' + schoolYearId],limit:1);
    if (managed.isNotEmpty || monthlyDates.isNotEmpty) {
      throw StateError('Cette année scolaire possède un calendrier automatique. Utilisez « Calendrier de facturation » pour compléter les échéanciers sans doublons.');
    }
    final students = await db.rawQuery('''
      SELECT s.id student_id, s.family_id, se.classroom_id, c.cycle_id
      FROM student_enrollments se
      JOIN students s ON s.id = se.student_id
      JOIN classrooms c ON c.id = se.classroom_id
      WHERE se.school_year_id = ?
        AND se.status = 'active'
        AND se.effective_from <= ?
        AND (se.effective_to IS NULL OR se.effective_to >= ?)
      ORDER BY s.id
    ''', [schoolYearId, effectiveDate.toIso8601String(), effectiveDate.toIso8601String()]);

    var candidates = 0;
    var existing = 0;
    var total = 0;
    final familyPackagesSeen = <String>{};
    for (final student in students) {
      final grids = await db.rawQuery('''
        SELECT g.* FROM fee_grid g
        JOIN fee_categories f ON f.id = g.fee_id
        WHERE f.active = 1
          AND f.periodicity = ?
          AND g.valid_from <= ?
          AND (g.valid_to IS NULL OR g.valid_to >= ?)
          AND ((g.classroom_id IS NOT NULL AND g.classroom_id = ?)
            OR (g.classroom_id IS NULL AND g.cycle_id = ?))
        ORDER BY CASE WHEN g.classroom_id IS NOT NULL THEN 0 ELSE 1 END,
                 g.valid_from DESC
      ''', [periodicity, effectiveDate.toIso8601String(), effectiveDate.toIso8601String(), student['classroom_id'], student['cycle_id']]);
      final seenFees = <String>{};
      for (final grid in grids) {
        final feeId = grid['fee_id'] as String;
        if (!seenFees.add(feeId)) continue;
        Map<String, Object?>? package;
        final familyId = student['family_id'] as String?;
        if (familyId != null) {
          final familyRows = await db.rawQuery('''
            SELECT * FROM packages
            WHERE active=1 AND type='family' AND family_id=? AND fee_id=?
              AND valid_from<=? AND (valid_to IS NULL OR valid_to>=?)
            ORDER BY valid_from DESC, created_at DESC LIMIT 1
          ''', [familyId, feeId, effectiveDate.toIso8601String(), effectiveDate.toIso8601String()]);
          if (familyRows.isNotEmpty) package = familyRows.first;
        }
        if (package == null) {
          final individualRows = await db.rawQuery('''
            SELECT * FROM packages
            WHERE active=1 AND type='individual' AND student_id=? AND fee_id=?
              AND valid_from<=? AND (valid_to IS NULL OR valid_to>=?)
            ORDER BY valid_from DESC, created_at DESC LIMIT 1
          ''', [student['student_id'], feeId, effectiveDate.toIso8601String(), effectiveDate.toIso8601String()]);
          if (individualRows.isNotEmpty) package = individualRows.first;
        }

        if (package != null && package['type'] == 'family') {
          final familyKey = '${package['id']}/$feeId/$periodKey/$schoolYearId';
          if (!familyPackagesSeen.add(familyKey)) continue;
        }

        final duplicate = firstIntValue(await db.rawQuery(
              '''SELECT COUNT(*) FROM dues
                 WHERE student_id=? AND fee_id=? AND period_key=? AND school_year_id=?''',
              [student['student_id'], feeId, periodKey, schoolYearId],
            )) ??
            0;
        if (duplicate > 0) {
          existing++;
          continue;
        }
        if (package != null && package['type'] == 'family') {
          final familyDuplicate = firstIntValue(await db.rawQuery(
                '''SELECT COUNT(*) FROM dues
                   WHERE package_id=? AND fee_id=? AND period_key=? AND school_year_id=?''',
                [package['id'], feeId, periodKey, schoolYearId],
              )) ??
              0;
          if (familyDuplicate > 0) {
            existing++;
            continue;
          }
        }
        final amount = package == null ? grid['amount'] as int : package['amount'] as int;
        candidates++;
        total += amount;
      }
    }
    return DueGenerationPreview(
      schoolYearId: schoolYearId,
      schoolYearLabel: schoolYear['label'] as String,
      periodKey: periodKey,
      periodicity: periodicity,
      studentCount: students.length,
      candidateCount: candidates,
      alreadyExistingCount: existing,
      totalAmount: total,
    );
  }

  /// Génère les échéances (dues) pour tous les élèves actifs, à partir de la
  /// grille tarifaire en vigueur à `dueDate`, pour la période `periodKey`
  /// (ex: '2026-09' pour un mois, '2026-T1' pour un trimestre, '2026' pour
  /// l'année). Idempotent : une échéance déjà générée pour un même élève,
  /// une même rubrique et une même période n'est jamais dupliquée.
  Future<int> generateDues({
    required String periodKey,
    required String periodicity,
    required DateTime dueDate,
    DateTime? referenceDate,
  }) async {
    _requireDirector();
    final db = _database.db;
    // La date de référence sert à choisir le tarif et le forfait en vigueur.
    // Elle est volontairement distincte de la date limite de paiement : une
    // échéance d'octobre ne doit pas utiliser par erreur le tarif du jour où
    // le gestionnaire lance la génération.
    final effectiveDate = referenceDate ?? dueDate;
    if (dueDate.isBefore(effectiveDate)) {
      throw StateError('La date limite ne peut pas précéder la période facturée.');
    }
    final schoolYear = await _schoolYearForDate(db, effectiveDate);
    if (schoolYear == null) {
      throw StateError('Créez et activez une année scolaire avant de générer les échéances.');
    }
    final schoolYearId = schoolYear['id'] as String;
    final managed = await db.query('billing_calendar_rules', columns:['id'],
        where:'school_year_id=? AND enabled=1', whereArgs:[schoolYearId], limit:1);
    final monthlyDates = await db.query('app_settings', columns:['key'],
        where:'key=?',whereArgs:['billing_month_deadlines:' + schoolYearId],limit:1);
    if (managed.isNotEmpty || monthlyDates.isNotEmpty) {
      throw StateError('Cette année scolaire possède un calendrier automatique. Utilisez « Calendrier de facturation » pour compléter les échéanciers sans doublons.');
    }
    final schoolYearStart = DateTime.parse(schoolYear['start_date'] as String);
    final schoolYearEnd = DateTime.parse(schoolYear['end_date'] as String);
    if (effectiveDate.isBefore(schoolYearStart) || effectiveDate.isAfter(schoolYearEnd)) {
      throw StateError('La période sélectionnée est hors de l’année scolaire ${schoolYear['label']}.');
    }
    var created = 0;
    var totalAmount = 0;
    final batchId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    // La classe utilisée est celle de l'inscription de l'année scolaire, et
    // non la classe courante mise en cache dans students. Ainsi une ancienne
    // année ne change jamais lorsqu'un élève est réinscrit l'année suivante.
    final students = await db.rawQuery('''
      SELECT s.id student_id, s.family_id, se.classroom_id, c.cycle_id
      FROM student_enrollments se
      JOIN students s ON s.id = se.student_id
      JOIN classrooms c ON c.id = se.classroom_id
      WHERE se.school_year_id = ?
        AND se.status = 'active'
        AND se.effective_from <= ?
        AND (se.effective_to IS NULL OR se.effective_to >= ?)
      ORDER BY s.id
    ''', [schoolYearId, effectiveDate.toIso8601String(), effectiveDate.toIso8601String()]);
    await db.transaction((txn) async {
      await txn.insert('billing_batches', {
        'id': batchId,
        'school_year_id': schoolYearId,
        'period_key': periodKey,
        'periodicity': periodicity,
        'reference_date': effectiveDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'generated_count': 0,
        'total_amount': 0,
        'status': 'posted',
        'created_by': OperatorSession.userId,
        'created_at': now,
      });
      for (final s in students) {
        final grids = await txn.rawQuery('''
          SELECT g.* FROM fee_grid g
          JOIN fee_categories f ON f.id = g.fee_id
          WHERE f.active = 1
            AND f.periodicity = ?
            AND g.valid_from <= ?
            AND (g.valid_to IS NULL OR g.valid_to >= ?)
            AND ((g.classroom_id IS NOT NULL AND g.classroom_id = ?) OR (g.classroom_id IS NULL AND g.cycle_id = ?))
          ORDER BY CASE WHEN g.classroom_id IS NOT NULL THEN 0 ELSE 1 END, g.valid_from DESC
        ''', [periodicity, effectiveDate.toIso8601String(), effectiveDate.toIso8601String(), s['classroom_id'], s['cycle_id']]);
        final seen = <String>{};
        for (final g in grids) {
          final feeId = g['fee_id'] as String;
          if (!seen.add(feeId)) continue;

          Map<String, Object?>? package;
          final familyId = s['family_id'] as String?;
          if (familyId != null) {
            final familyPackages = await txn.rawQuery('''
              SELECT * FROM packages
              WHERE active = 1 AND type = 'family' AND family_id = ? AND fee_id = ?
                AND valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)
              ORDER BY valid_from DESC, created_at DESC LIMIT 1
            ''', [familyId, feeId, effectiveDate.toIso8601String(), effectiveDate.toIso8601String()]);
            if (familyPackages.isNotEmpty) package = familyPackages.first;
          }
          if (package == null) {
            final individualPackages = await txn.rawQuery('''
              SELECT * FROM packages
              WHERE active = 1 AND type = 'individual' AND student_id = ? AND fee_id = ?
                AND valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)
              ORDER BY valid_from DESC, created_at DESC LIMIT 1
            ''', [s['student_id'], feeId, effectiveDate.toIso8601String(), effectiveDate.toIso8601String()]);
            if (individualPackages.isNotEmpty) package = individualPackages.first;
          }

          // Un forfait familial représente une dette unique pour toute la
          // famille. On l'attache au premier élève éligible uniquement afin
          // d'éviter toute double facturation, tout en conservant family_id
          // pour que l'encaissement familial solde correctement cette dette.
          if (package != null && package['type'] == 'family') {
            final existing = firstIntValue(await txn.rawQuery(
                  'SELECT COUNT(*) FROM dues WHERE package_id = ? AND fee_id = ? AND period_key = ? AND school_year_id = ?',
                  [package['id'], feeId, periodKey, schoolYearId],
                )) ??
                0;
            if (existing > 0) continue;
          }

          final amountDue = package == null ? g['amount'] as int : package['amount'] as int;
          final n = await txn.insert(
            'dues',
            {
              'id': _uuid.v4(),
              'student_id': s['student_id'],
              'family_id': s['family_id'],
              'fee_id': feeId,
              'package_id': package == null ? null : package['id'],
              'school_year_id': schoolYearId,
              'billing_batch_id': batchId,
              'period_key': periodKey,
              'amount_due': amountDue,
              'amount_paid': 0,
              'due_date': dueDate.toIso8601String(),
              'status': 'unpaid',
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (n > 0) {
            created++;
            totalAmount += amountDue;
          }
        }
      }
      if (created == 0) {
        await txn.delete('billing_batches', where: 'id=?', whereArgs: [batchId]);
      } else {
        await txn.update(
          'billing_batches',
          {'generated_count': created, 'total_amount': totalAmount},
          where: 'id=?',
          whereArgs: [batchId],
        );
      }
      await txn.insert('audit_log', {
        'entity_type': 'dues',
        'entity_id': periodKey,
        'action': 'generate',
        'new_value': '$created échéance(s) $periodicity générée(s) pour $periodKey; lot=$batchId; année=${schoolYear['label']}; référence=${effectiveDate.toIso8601String()}; échéance=${dueDate.toIso8601String()}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
    return created;
  }

  Future<List<BillingBatchItem>> billingBatches({int limit = 30}) async {
    final rows = await _database.db.rawQuery('''
      SELECT b.*, sy.label school_year_label
      FROM billing_batches b
      JOIN school_years sy ON sy.id=b.school_year_id
      ORDER BY b.created_at DESC
      LIMIT ?
    ''', [limit]);
    return rows
        .map(
          (row) => BillingBatchItem(
            id: row['id'] as String,
            schoolYearLabel: row['school_year_label'] as String,
            periodKey: row['period_key'] as String,
            periodicity: row['periodicity'] as String,
            dueDate: DateTime.parse(row['due_date'] as String),
            generatedCount: row['generated_count'] as int,
            totalAmount: row['total_amount'] as int,
            status: row['status'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }

  Future<void> cancelBillingBatch(String batchId) async {
    BusinessWriteGuard.ensureAllowed('cancelBillingBatch');
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final batchRows = await txn.query('billing_batches', where: 'id=?', whereArgs: [batchId], limit: 1);
      if (batchRows.isEmpty) throw StateError('Lot de facturation introuvable.');
      if (batchRows.first['status'] != 'posted') throw StateError('Ce lot est déjà annulé.');
      final paid = firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM dues WHERE billing_batch_id=? AND amount_paid>0',
            [batchId],
          )) ??
          0;
      if (paid > 0) {
        throw StateError('Impossible d’annuler ce lot : au moins une échéance a déjà reçu un paiement ou un avoir.');
      }
      await txn.delete('dues', where: 'billing_batch_id=?', whereArgs: [batchId]);
      await txn.update(
        'billing_batches',
        {'status': 'cancelled', 'cancelled_at': now},
        where: 'id=?',
        whereArgs: [batchId],
      );
      await txn.insert('audit_log', {
        'entity_type': 'billing_batch',
        'entity_id': batchId,
        'action': 'cancel',
        'old_value': '${batchRows.first['period_key']}/${batchRows.first['generated_count']}/${batchRows.first['total_amount']}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<List<DueItem>> dues({bool unpaidOnly = false}) async {
    final yearId = await _activeSchoolYearId(_database.db);
    final conditions = <String>[];
    final args = <Object?>[];
    if (yearId != null) {
      conditions.add('d.school_year_id = ?');
      args.add(yearId);
    }
    if (unpaidOnly) conditions.add("d.status != 'paid'");
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await _database.db.rawQuery('''
      SELECT d.*,
             CASE WHEN p.type = 'family' THEN 'Famille ' || COALESCE(fam.name, '') || ' (forfait)'
                  ELSE s.last_name || ' ' || s.first_name END student_name,
             f.name fee_name
      FROM dues d
      JOIN students s ON s.id = d.student_id
      JOIN fee_categories f ON f.id = d.fee_id
      LEFT JOIN packages p ON p.id = d.package_id
      LEFT JOIN families fam ON fam.id = d.family_id
      $where
      ORDER BY d.due_date, d.period_key, s.last_name
    ''', args);
    return rows
        .map((r) => DueItem(
              id: r['id'] as String,
              studentId: r['student_id'] as String,
              studentName: r['student_name'] as String,
              feeName: r['fee_name'] as String,
              periodKey: r['period_key'] as String,
              amountDue: r['amount_due'] as int,
              amountPaid: r['amount_paid'] as int,
              status: r['status'] as String,
              dueDate: r['due_date'] == null ? null : DateTime.parse(r['due_date'] as String),
            ))
        .toList();
  }

  // --- Encaissements -------------------------------------------------------

  Future<String> _nextReceiptNumber(DatabaseExecutor db) async {
    final year = DateTime.now().year;
    final key = 'receipt_sequence_$year';
    final rows = await db.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    var current = rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
    if (current == 0) {
      final existing = await db.rawQuery(
        "SELECT receipt_number FROM payments WHERE receipt_number LIKE ? ORDER BY receipt_number DESC LIMIT 1",
        ['REC-$year-%'],
      );
      if (existing.isNotEmpty) {
        final value = existing.first['receipt_number'] as String? ?? '';
        current = int.tryParse(value.split('-').last) ?? 0;
      }
    }
    final next = current + 1;
    await db.insert(
      'app_settings',
      {'key': key, 'value': next.toString(), 'updated_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return 'REC-$year-${next.toString().padLeft(6, '0')}';
  }

  Future<void> _allocateToDues(Transaction txn, {required String paymentId, required int amount, required String duesWhere, required List<Object?> duesArgs}) async {
    var remaining = amount;
    final now = DateTime.now().toIso8601String();
    final dueRows = await txn.query('dues', where: duesWhere, whereArgs: duesArgs, orderBy: 'period_key ASC, due_date ASC, created_at ASC');
    for (final due in dueRows) {
      if (remaining <= 0) break;
      final balance = (due['amount_due'] as int) - (due['amount_paid'] as int);
      if (balance <= 0) continue;
      final alloc = remaining < balance ? remaining : balance;
      remaining -= alloc;
      final newPaid = (due['amount_paid'] as int) + alloc;
      final total = due['amount_due'] as int;
      await txn.insert('payment_allocations', {'payment_id': paymentId, 'due_id': due['id'], 'amount': alloc});
      await txn.update(
        'dues',
        {'amount_paid': newPaid, 'status': newPaid >= total ? 'paid' : 'partial', 'updated_at': now},
        where: 'id = ?',
        whereArgs: [due['id']],
      );
    }
  }


  Future<List<Map<String,Object?>>> paymentMethods() => _database.db.query('payment_methods', where:'active = 1', orderBy:'name');
  Future<List<Map<String,Object?>>> cashAccounts() => _database.db.query('cash_accounts', where:'active = 1', orderBy:'name');
  Future<List<DueItem>> unpaidForPayer({String? studentId,String? familyId,bool includePaid=false}) async {
    final yearId = await _activeSchoolYearId(_database.db);
    final yearSql = yearId == null ? '' : ' AND d.school_year_id = ?';
    final payerArgs = <Object?>[studentId ?? familyId, includePaid ? 1 : 0];
    if (yearId != null) payerArgs.add(yearId);
    final rows = studentId != null
      ? await _database.db.rawQuery("SELECT d.*, s.last_name || ' ' || s.first_name student_name, f.name fee_name FROM dues d JOIN students s ON s.id=d.student_id JOIN fee_categories f ON f.id=d.fee_id WHERE d.student_id=? AND ( ? = 1 OR d.status!='paid') AND (d.package_id IS NULL OR d.package_id NOT IN (SELECT id FROM packages WHERE type='family'))$yearSql ORDER BY d.period_key,d.due_date,d.created_at",payerArgs)
      : await _database.db.rawQuery("SELECT d.*, s.last_name || ' ' || s.first_name student_name, f.name fee_name FROM dues d JOIN students s ON s.id=d.student_id JOIN fee_categories f ON f.id=d.fee_id WHERE d.family_id=? AND ( ? = 1 OR d.status!='paid')$yearSql ORDER BY d.period_key,d.due_date,d.created_at",payerArgs);
    return rows.map((r)=>DueItem(id:r['id'] as String,studentId:r['student_id'] as String,studentName:r['student_name'] as String,feeName:r['fee_name'] as String,feeId:r['fee_id'] as String,periodKey:r['period_key'] as String,amountDue:r['amount_due'] as int,amountPaid:r['amount_paid'] as int,status:r['status'] as String,dueDate:r['due_date']==null?null:DateTime.parse(r['due_date'] as String))).toList();
  }
  Future<int> availableCredit({String? studentId,String? familyId}) async => firstIntValue(await _database.db.rawQuery("SELECT COALESCE(SUM(amount),0) FROM payer_credits WHERE status='available' AND ${studentId!=null?'student_id':'family_id'} = ?",[studentId??familyId]))??0;

  Future<int> outstandingForStudent(String studentId) async {
    final yearId = await _activeSchoolYearId(_database.db);
    return firstIntValue(await _database.db.rawQuery('''
      SELECT COALESCE(SUM(amount_due - amount_paid), 0)
      FROM dues
      WHERE student_id = ? AND status != 'paid'
        AND (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))
        ${yearId == null ? '' : 'AND school_year_id = ?'}
    ''', yearId == null ? [studentId] : [studentId, yearId])) ?? 0;
  }

  Future<int> outstandingForFamily(String familyId) async {
    final yearId = await _activeSchoolYearId(_database.db);
    return firstIntValue(await _database.db.rawQuery(
          "SELECT COALESCE(SUM(amount_due - amount_paid), 0) FROM dues WHERE family_id = ? AND status != 'paid' ${yearId == null ? '' : 'AND school_year_id = ?'}",
          yearId == null ? [familyId] : [familyId, yearId],
        )) ??
        0;
  }

  Future<int> _selectedOutstandingForPayer(
    Transaction txn, {
    required List<String> dueIds,
    required String schoolYearId,
    String? studentId,
    String? familyId,
  }) async {
    if (dueIds.isEmpty) return 0;
    if ((studentId == null) == (familyId == null)) {
      throw ArgumentError('Indiquez exactement un payeur.');
    }
    final uniqueIds = dueIds.toSet().toList(growable: false);
    if (uniqueIds.length != dueIds.length) {
      throw StateError('La sélection contient des échéances en double.');
    }
    final placeholders = List.filled(uniqueIds.length, '?').join(',');
    final payerColumn = studentId != null ? 'student_id' : 'family_id';
    final payerId = studentId ?? familyId!;
    final packageFilter = studentId != null
        ? " AND (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))"
        : '';
    final rows = await txn.rawQuery('''
      SELECT COUNT(*) AS valid_count,
             COALESCE(SUM(amount_due - amount_paid), 0) AS outstanding
      FROM dues
      WHERE id IN ($placeholders)
        AND school_year_id = ?
        AND $payerColumn = ?
        AND status != 'paid'
        $packageFilter
    ''', [...uniqueIds, schoolYearId, payerId]);
    final validCount = firstIntValue(rows) ?? 0;
    if (validCount != uniqueIds.length) {
      throw StateError(
        'Une ou plusieurs échéances sélectionnées n’appartiennent pas au payeur, '
        'à l’année scolaire active, ou ne sont plus payables.',
      );
    }
    return (rows.first['outstanding'] as num?)?.toInt() ?? 0;
  }

  /// Encaissement pour un élève individuel. Pour cette release candidate,
  /// toute avance non allouée est interdite : un paiement doit correspondre
  /// à des échéances existantes et ne peut pas dépasser le solde restant.
  Future<String> recordPayment({required String studentId, required int amount, required String method, String? note, List<String>? dueIds, String? cashAccountId, String? transactionReference, String? payerPhone, String? paymentOperator}) async {
    _requireCollectionPermission();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Le montant doit être positif');
    final db = _database.db;
    final now = DateTime.now();
    final id = _uuid.v4();
    late String receipt;
    await db.transaction((txn) async {
      final yearId = await _activeSchoolYearId(txn);
      if (yearId == null) throw StateError('Aucune année scolaire active.');
      final outstanding = firstIntValue(await txn.rawQuery('''
        SELECT COALESCE(SUM(amount_due - amount_paid), 0)
        FROM dues
        WHERE student_id = ? AND status != 'paid'
          AND school_year_id = ?
          AND (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))
      ''', [studentId, yearId])) ?? 0;

      await ensurePaymentMethodMatchesAccount(txn, method, cashAccountId);
      if (await paymentMethodRequiresReference(txn, method) && (transactionReference ?? '').trim().isEmpty) {
        throw StateError('Une référence de transaction est obligatoire pour « $method ».');
      }
      await ensureCashMovementAllowed(txn, cashAccountId);
      receipt = await _nextReceiptNumber(txn);
      await txn.insert('payments', {
        'id': id,
        'receipt_number': receipt,
        'student_id': studentId,
        'school_year_id': yearId,
        'amount': amount,
        'payment_method': method,
        'paid_at': now.toIso8601String(),
        'note': note?.trim(),
        'cash_account_id': cashAccountId,
        'transaction_reference': transactionReference?.trim(),
        'payer_phone': payerPhone?.trim(),
        'payment_operator': paymentOperator?.trim(),
        'credit_amount': amount > outstanding ? amount - outstanding : 0,
        'status': 'posted',
        'created_at': now.toIso8601String(),
      });
      final selected = dueIds;
      final selectedOutstanding = selected == null
          ? outstanding
          : await _selectedOutstandingForPayer(
              txn,
              dueIds: selected,
              schoolYearId: yearId,
              studentId: studentId,
            );
      if (selected == null || selected.isNotEmpty) {
        await _allocateToDues(
          txn,
          paymentId: id,
          amount: amount,
          duesWhere: selected == null
              ? "student_id = ? AND school_year_id = ? AND status != ? AND (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))"
              : "id IN (${List.filled(selected.length, '?').join(',')}) AND school_year_id = ? AND student_id = ? AND status != ? AND (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))",
          duesArgs: selected == null
              ? [studentId, yearId, 'paid']
              : [...selected, yearId, studentId, 'paid'],
        );
      }
      final credit = amount > selectedOutstanding ? amount-selectedOutstanding : 0;
      await txn.update('payments',{'credit_amount':credit},where:'id = ?',whereArgs:[id]);
      if(credit>0) await txn.insert('payer_credits',{'id':_uuid.v4(),'student_id':studentId,'amount':credit,'source_payment_id':id,'status':'available','created_at':now.toIso8601String()});
      await txn.insert('audit_log', {
        'entity_type': 'payment',
        'entity_id': id,
        'action': 'create',
        'new_value': '$amount/$method/$receipt',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now.toIso8601String(),
      });
    });
    return receipt;
  }

  /// Encaissement au nom d'une famille : le montant est réparti entre les
  /// échéances de tous les enfants de la famille, de la plus ancienne à la
  /// plus récente, ce qui évite d'avoir à encaisser élève par élève pour une
  /// fratrie.
  Future<String> recordFamilyPayment({required String familyId, required int amount, required String method, String? note, List<String>? dueIds, String? cashAccountId, String? transactionReference, String? payerPhone, String? paymentOperator}) async {
    _requireCollectionPermission();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Le montant doit être positif');
    final db = _database.db;
    final now = DateTime.now();
    final id = _uuid.v4();
    late String receipt;
    await db.transaction((txn) async {
      final yearId = await _activeSchoolYearId(txn);
      if (yearId == null) throw StateError('Aucune année scolaire active.');
      final outstanding = firstIntValue(await txn.rawQuery(
            "SELECT COALESCE(SUM(amount_due - amount_paid), 0) FROM dues WHERE family_id = ? AND school_year_id = ? AND status != 'paid'",
            [familyId, yearId],
          )) ??
          0;

      await ensurePaymentMethodMatchesAccount(txn, method, cashAccountId);
      if (await paymentMethodRequiresReference(txn, method) && (transactionReference ?? '').trim().isEmpty) {
        throw StateError('Une référence de transaction est obligatoire pour « $method ».');
      }
      await ensureCashMovementAllowed(txn, cashAccountId);
      receipt = await _nextReceiptNumber(txn);
      await txn.insert('payments', {
        'id': id,
        'receipt_number': receipt,
        'family_id': familyId,
        'school_year_id': yearId,
        'amount': amount,
        'payment_method': method,
        'paid_at': now.toIso8601String(),
        'note': note?.trim(),
        'cash_account_id': cashAccountId,
        'transaction_reference': transactionReference?.trim(),
        'payer_phone': payerPhone?.trim(),
        'payment_operator': paymentOperator?.trim(),
        'credit_amount': amount > outstanding ? amount - outstanding : 0,
        'status': 'posted',
        'created_at': now.toIso8601String(),
      });
      final selected = dueIds;
      final selectedOutstanding = selected == null
          ? outstanding
          : await _selectedOutstandingForPayer(
              txn,
              dueIds: selected,
              schoolYearId: yearId,
              familyId: familyId,
            );
      if (selected == null || selected.isNotEmpty) {
        await _allocateToDues(
          txn,
          paymentId: id,
          amount: amount,
          duesWhere: selected == null
              ? 'family_id = ? AND school_year_id = ? AND status != ?'
              : "id IN (${List.filled(selected.length, '?').join(',')}) AND school_year_id = ? AND family_id = ? AND status != ?",
          duesArgs: selected == null
              ? [familyId, yearId, 'paid']
              : [...selected, yearId, familyId, 'paid'],
        );
      }
      final credit=amount>selectedOutstanding?amount-selectedOutstanding:0;
      await txn.update('payments',{'credit_amount':credit},where:'id = ?',whereArgs:[id]);
      if(credit>0) await txn.insert('payer_credits',{'id':_uuid.v4(),'family_id':familyId,'amount':credit,'source_payment_id':id,'status':'available','created_at':now.toIso8601String()});
      await txn.insert('audit_log', {
        'entity_type': 'payment',
        'entity_id': id,
        'action': 'create_family',
        'new_value': '$amount/$method/$receipt',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now.toIso8601String(),
      });
    });
    return receipt;
  }

  /// Annule (contre-passe) un paiement déjà encaissé : les échéances qui
  /// avaient été soldées par ce paiement redeviennent impayées/partielles à
  /// hauteur du montant annulé, et une trace explicite est conservée dans le
  /// journal d'audit avec le motif fourni. Le paiement lui-même n'est jamais
  /// supprimé (traçabilité), seul son statut passe à « annule ».

  /// Applique les avoirs disponibles aux échéances encore dues sans créer
  /// une nouvelle recette. L'argent a déjà été encaissé dans le paiement qui
  /// a généré l'avoir ; seule la dette est soldée ici.
  Future<int> applyAvailableCredit({
    String? studentId,
    String? familyId,
    List<String>? dueIds,
  }) async {
    _requireCollectionPermission();
    if ((studentId == null) == (familyId == null)) {
      throw ArgumentError('Indiquez soit un élève, soit une famille.');
    }
    final now = DateTime.now().toIso8601String();
    var appliedTotal = 0;
    await _database.db.transaction((txn) async {
      final yearId = await _activeSchoolYearId(txn);
      if (yearId == null) throw StateError('Aucune année scolaire active.');

      final creditWhere = studentId != null
          ? "student_id = ? AND status = 'available' AND amount > 0"
          : "family_id = ? AND status = 'available' AND amount > 0";
      final credits = await txn.query(
        'payer_credits',
        where: creditWhere,
        whereArgs: [studentId ?? familyId],
        orderBy: 'created_at ASC',
      );
      if (credits.isEmpty) throw StateError('Aucun avoir disponible.');

      final selected = dueIds?.where((id) => id.trim().isNotEmpty).toList();
      final clauses = <String>[
        studentId != null ? 'd.student_id = ?' : 'd.family_id = ?',
        'd.school_year_id = ?',
        "d.status != 'paid'",
      ];
      final args = <Object?>[studentId ?? familyId, yearId];
      if (studentId != null) {
        clauses.add("(d.package_id IS NULL OR d.package_id NOT IN (SELECT id FROM packages WHERE type='family'))");
      }
      if (selected != null) {
        if (selected.isEmpty) throw StateError('Sélectionnez au moins une échéance.');
        clauses.add("d.id IN (${List.filled(selected.length, '?').join(',')})");
        args.addAll(selected);
      }
      final dues = await txn.rawQuery(
        "SELECT d.* FROM dues d WHERE ${clauses.join(' AND ')} ORDER BY d.period_key, d.due_date, d.created_at",
        args,
      );
      if (dues.isEmpty) throw StateError('Aucune échéance à solder avec cet avoir.');

      var creditIndex = 0;
      var creditRemaining = credits.first['amount'] as int;
      for (final due in dues) {
        var dueBalance = (due['amount_due'] as int) - (due['amount_paid'] as int);
        if (dueBalance <= 0) continue;
        while (dueBalance > 0 && creditIndex < credits.length) {
          if (creditRemaining <= 0) {
            creditIndex++;
            if (creditIndex >= credits.length) break;
            creditRemaining = credits[creditIndex]['amount'] as int;
            continue;
          }
          final use = creditRemaining < dueBalance ? creditRemaining : dueBalance;
          final credit = credits[creditIndex];
          creditRemaining -= use;
          dueBalance -= use;
          appliedTotal += use;

          await txn.insert('payer_credit_allocations', {
            'id': _uuid.v4(),
            'credit_id': credit['id'],
            'due_id': due['id'],
            'amount': use,
            'applied_at': now,
            'operator_id': OperatorSession.userId,
          });
          await txn.update(
            'payer_credits',
            {
              'amount': creditRemaining,
              'status': creditRemaining == 0 ? 'used' : 'available',
            },
            where: 'id = ?',
            whereArgs: [credit['id']],
          );
          final newPaid = (due['amount_due'] as int) - dueBalance;
          await txn.update(
            'dues',
            {
              'amount_paid': newPaid,
              'status': dueBalance == 0 ? 'paid' : 'partial',
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [due['id']],
          );
        }
        if (creditIndex >= credits.length) break;
      }
      if (appliedTotal <= 0) throw StateError('Aucun avoir n’a pu être appliqué.');
      await txn.insert('audit_log', {
        'entity_type': studentId != null ? 'student_credit' : 'family_credit',
        'entity_id': studentId ?? familyId!,
        'action': 'apply_credit',
        'new_value': appliedTotal.toString(),
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
    return appliedTotal;
  }

  Future<int> refundableAmount(String paymentId) async {
    final rows = await _database.db.rawQuery("SELECT p.amount - COALESCE((SELECT SUM(r.amount) FROM payment_refunds r WHERE r.payment_id=p.id),0) remaining FROM payments p WHERE p.id=? AND p.status='posted' LIMIT 1", [paymentId]);
    if (rows.isEmpty) return 0;
    final value = rows.first['remaining'] as int? ?? 0;
    return value < 0 ? 0 : value;
  }

  Future<List<Map<String, Object?>>> paymentRefunds(String paymentId) => _database.db.query(
    'payment_refunds',
    where: 'payment_id=?',
    whereArgs: [paymentId],
    orderBy: 'refunded_at DESC',
  );

  Future<void> refundPayment({
    required String paymentId,
    required int amount,
    required String reason,
    String? paymentMethod,
    String? cashAccountId,
    String? transactionReference,
  }) async {
    BusinessWriteGuard.ensureAllowed('refundPayment');
    if (amount <= 0 || reason.trim().isEmpty) {
      throw ArgumentError('Montant et motif obligatoires.');
    }
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final payments = await txn.query(
        'payments',
        where: "id = ? AND status = 'posted'",
        whereArgs: [paymentId],
        limit: 1,
      );
      if (payments.isEmpty) {
        throw StateError('Paiement introuvable ou annulé.');
      }
      final effectiveMethod = (paymentMethod ?? payments.first['payment_method'] as String?)?.trim();
      final effectiveAccount = cashAccountId ?? payments.first['cash_account_id'] as String?;
      if (effectiveMethod != null && effectiveMethod.isNotEmpty) {
        await ensurePaymentMethodMatchesAccount(txn, effectiveMethod, effectiveAccount);
        if (await paymentMethodRequiresReference(txn, effectiveMethod) && (transactionReference ?? '').trim().isEmpty) {
          throw StateError('Une référence est obligatoire pour le moyen de remboursement « $effectiveMethod ».');
        }
      }
      await ensureCashMovementAllowed(txn, effectiveAccount);

      final refunded = firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(SUM(amount),0) FROM payment_refunds WHERE payment_id = ?',
              [paymentId],
            ),
          ) ??
          0;
      if (refunded + amount > (payments.first['amount'] as int)) {
        throw StateError('Le remboursement dépasse le montant encore remboursable.');
      }

      var remaining = amount;
      final credits = await txn.query(
        'payer_credits',
        where: "source_payment_id = ? AND status = 'available'",
        whereArgs: [paymentId],
      );
      for (final credit in credits) {
        if (remaining <= 0) {
          break;
        }
        final available = credit['amount'] as int;
        final take = remaining < available ? remaining : available;
        remaining -= take;
        final nextAmount = available - take;
        await txn.update(
          'payer_credits',
          {'amount': nextAmount, 'status': nextAmount == 0 ? 'used' : 'available'},
          where: 'id = ?',
          whereArgs: [credit['id']],
        );
      }

      if (remaining > 0) {
        final usedCreditAllocations = await txn.rawQuery('''
          SELECT pca.id allocation_id, pca.credit_id, pca.due_id, pca.amount,
                 pc.amount credit_remaining
          FROM payer_credit_allocations pca
          JOIN payer_credits pc ON pc.id = pca.credit_id
          WHERE pc.source_payment_id = ?
          ORDER BY pca.applied_at DESC, pca.rowid DESC
        ''', [paymentId]);
        for (final allocation in usedCreditAllocations) {
          if (remaining <= 0) break;
          final allocated = allocation['amount'] as int;
          final take = remaining < allocated ? remaining : allocated;
          remaining -= take;
          final dueRows = await txn.query(
            'dues',
            where: 'id = ?',
            whereArgs: [allocation['due_id']],
            limit: 1,
          );
          if (dueRows.isNotEmpty) {
            final due = dueRows.first;
            final total = due['amount_due'] as int;
            final newPaid = ((due['amount_paid'] as int) - take).clamp(0, total);
            await txn.update(
              'dues',
              {
                'amount_paid': newPaid,
                'status': newPaid == 0 ? 'unpaid' : (newPaid >= total ? 'paid' : 'partial'),
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [due['id']],
            );
          }
          if (take == allocated) {
            await txn.delete(
              'payer_credit_allocations',
              where: 'id = ?',
              whereArgs: [allocation['allocation_id']],
            );
          } else {
            await txn.update(
              'payer_credit_allocations',
              {'amount': allocated - take},
              where: 'id = ?',
              whereArgs: [allocation['allocation_id']],
            );
          }
          // La partie d’avoir annulée est remboursée en argent : elle ne
          // redevient donc pas un avoir disponible.
        }
      }

      if (remaining > 0) {
        final allocations = await txn.query(
          'payment_allocations',
          where: 'payment_id = ?',
          whereArgs: [paymentId],
          orderBy: 'rowid DESC',
        );
        for (final allocation in allocations) {
          if (remaining <= 0) {
            break;
          }
          final allocated = allocation['amount'] as int;
          final take = remaining < allocated ? remaining : allocated;
          remaining -= take;
          final dueRows = await txn.query(
            'dues',
            where: 'id = ?',
            whereArgs: [allocation['due_id']],
            limit: 1,
          );
          if (dueRows.isEmpty) {
            continue;
          }
          final due = dueRows.first;
          final dueTotal = due['amount_due'] as int;
          final newPaid = ((due['amount_paid'] as int) - take).clamp(0, dueTotal);
          await txn.update(
            'dues',
            {
              'amount_paid': newPaid,
              'status': newPaid == 0 ? 'unpaid' : (newPaid >= dueTotal ? 'paid' : 'partial'),
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [due['id']],
          );
          if (take == allocated) {
            await txn.delete(
              'payment_allocations',
              where: 'payment_id = ? AND due_id = ?',
              whereArgs: [paymentId, allocation['due_id']],
            );
          } else {
            await txn.update(
              'payment_allocations',
              {'amount': allocated - take},
              where: 'payment_id = ? AND due_id = ?',
              whereArgs: [paymentId, allocation['due_id']],
            );
          }
        }
      }

      await txn.insert('payment_refunds', {
        'id': _uuid.v4(),
        'payment_id': paymentId,
        'amount': amount,
        'reason': reason.trim(),
        'refunded_at': now,
        'operator_id': OperatorSession.userId,
        'payment_method': effectiveMethod,
        'cash_account_id': effectiveAccount,
        'transaction_reference': transactionReference?.trim().isEmpty == true ? null : transactionReference?.trim(),
      });
      await txn.insert('audit_log', {
        'entity_type': 'payment',
        'entity_id': paymentId,
        'action': 'partial_refund',
        'new_value': '$amount/${reason.trim()}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<void> cancelPayment({
    required String paymentId, required String reason}) async {
      BusinessWriteGuard.ensureAllowed('cancelPayment');
      
    if (reason.trim().isEmpty) throw ArgumentError('Un motif d\'annulation est obligatoire');
    final db = _database.db;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final paymentRows = await txn.query('payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
      if (paymentRows.isEmpty) throw StateError('Paiement introuvable');
      final payment = paymentRows.first;
      if (payment['status'] == 'annule') throw StateError('Ce paiement est déjà annulé');
      await ensureCashMovementAllowed(txn, payment['cash_account_id'] as String?);
      final usedCredit = firstIntValue(await txn.rawQuery(
        'SELECT COALESCE(SUM(pca.amount),0) FROM payer_credit_allocations pca JOIN payer_credits pc ON pc.id=pca.credit_id WHERE pc.source_payment_id=?',
        [paymentId],
      )) ?? 0;
      if (usedCredit > 0) {
        throw StateError('Une partie de l’avoir issu de ce paiement a déjà été utilisée. Effectuez un remboursement partiel pour conserver une contre-passation cohérente.');
      }
      final alreadyRefunded = firstIntValue(await txn.rawQuery('SELECT COALESCE(SUM(amount),0) FROM payment_refunds WHERE payment_id=?', [paymentId])) ?? 0;
      if (alreadyRefunded > 0) {
        throw StateError('Ce paiement a déjà fait l’objet d’un remboursement partiel. Remboursez le solde restant au lieu de l’annuler entièrement.');
      }

      final allocations = await txn.query('payment_allocations', where: 'payment_id = ?', whereArgs: [paymentId]);
      for (final alloc in allocations) {
        final dueRows = await txn.query('dues', where: 'id = ?', whereArgs: [alloc['due_id']], limit: 1);
        if (dueRows.isEmpty) continue;
        final due = dueRows.first;
        final allocAmount = alloc['amount'] as int;
        final newPaid = ((due['amount_paid'] as int) - allocAmount).clamp(0, due['amount_due'] as int);
        final total = due['amount_due'] as int;
        final newStatus = newPaid <= 0 ? 'unpaid' : (newPaid >= total ? 'paid' : 'partial');
        await txn.update(
          'dues',
          {'amount_paid': newPaid, 'status': newStatus, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [due['id']],
        );
      }
      await txn.delete('payment_allocations', where: 'payment_id = ?', whereArgs: [paymentId]);
      await txn.update('payer_credits', {'status':'cancelled','amount':0}, where:'source_payment_id = ?', whereArgs:[paymentId]);

      await txn.update(
        'payments',
        {'status': 'annule', 'cancel_reason': reason.trim(), 'cancelled_at': now},
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      await txn.insert('audit_log', {
        'entity_type': 'payment',
        'entity_id': paymentId,
        'action': 'cancel',
        'old_value': '${payment['amount']}/${payment['payment_method']}/${payment['receipt_number']}',
        'new_value': reason.trim(),
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<List<Map<String, Object?>>> paymentReceiptLines(String receiptNumber) async {
    return _database.db.rawQuery('''
      SELECT f.name fee_name, d.period_key, pa.amount
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      JOIN dues d ON d.id = pa.due_id
      JOIN fee_categories f ON f.id = d.fee_id
      WHERE p.receipt_number = ?
      ORDER BY d.due_date, d.created_at
    ''', [receiptNumber]);
  }

  Future<ReceiptVerificationResult?> verifyReceipt(String receiptNumber) async {
    final normalized = receiptNumber.trim();
    if (normalized.isEmpty) return null;

    final rows = await _database.db.rawQuery('''
      SELECT
        p.id,
        p.receipt_number,
        p.amount,
        p.payment_method,
        p.paid_at,
        p.status,
        p.cancel_reason,
        p.transaction_reference,
        p.payer_phone,
        COALESCE(s.last_name || ' ' || s.first_name, fam.name, 'Famille') beneficiary_name,
        sy.label school_year_label,
        COALESCE((SELECT SUM(r.amount) FROM payment_refunds r WHERE r.payment_id = p.id), 0) refunded_amount
      FROM payments p
      LEFT JOIN students s ON s.id = p.student_id
      LEFT JOIN families fam ON fam.id = COALESCE(p.family_id, s.family_id)
      LEFT JOIN school_years sy ON sy.id = p.school_year_id
      WHERE lower(p.receipt_number) = lower(?)
      LIMIT 1
    ''', [normalized]);

    if (rows.isEmpty) return null;
    final row = rows.first;
    final allocationRows = await paymentReceiptLines(row['receipt_number'] as String);
    final lines = allocationRows
        .map((r) => ReceiptVerificationLine(
              label: '${r['fee_name']} · ${r['period_key']}',
              amount: r['amount'] as int,
            ))
        .toList(growable: false);

    return ReceiptVerificationResult(
      paymentId: row['id'] as String,
      receiptNumber: row['receipt_number'] as String,
      beneficiaryName: row['beneficiary_name'] as String,
      amount: row['amount'] as int,
      refundedAmount: (row['refunded_amount'] as int?) ?? 0,
      method: row['payment_method'] as String,
      paidAt: DateTime.parse(row['paid_at'] as String),
      status: row['status'] as String,
      cancelReason: row['cancel_reason'] as String?,
      transactionReference: row['transaction_reference'] as String?,
      payerPhone: row['payer_phone'] as String?,
      schoolYearLabel: row['school_year_label'] as String?,
      lines: lines,
    );
  }

  Future<List<PaymentItem>> searchPayments({String query='',bool cancelled=false,int limit=100,int offset=0,String? method,String? schoolYearId}) async {
    final where=<String>[cancelled ? "p.status='annule'" : "p.status='posted'"];final args=<Object?>[];final q=query.trim();
    if(q.isNotEmpty){where.add("(p.receipt_number LIKE ? OR COALESCE(s.last_name||' '||s.first_name,'') LIKE ? OR COALESCE(f.name,'') LIKE ? OR CAST(p.amount AS TEXT) LIKE ? OR COALESCE(p.transaction_reference,'') LIKE ?)");args.addAll(List.filled(5,'%$q%'));}
    if(method!=null&&method.isNotEmpty){where.add('p.payment_method=?');args.add(method);}if(schoolYearId!=null){where.add('p.school_year_id=?');args.add(schoolYearId);}
    final rows=await _database.db.rawQuery('''SELECT p.*,COALESCE(s.last_name||' '||s.first_name,f.name,'Famille') student_name,CASE WHEN p.family_id IS NOT NULL THEN 1 ELSE 0 END is_family,COALESCE((SELECT SUM(pr.amount) FROM payment_refunds pr WHERE pr.payment_id=p.id),0) refunded_amount FROM payments p LEFT JOIN students s ON s.id=p.student_id LEFT JOIN families f ON f.id=p.family_id WHERE ${where.join(' AND ')} ORDER BY ${cancelled?'p.cancelled_at':'p.paid_at'} DESC LIMIT ? OFFSET ?''',[...args,limit,offset]);
    return rows.map(_paymentFromRow).toList();
  }

  Future<List<PaymentItem>> recentPayments({int limit = 100}) async {
    final rows = await _database.db.rawQuery('''
      SELECT p.*, COALESCE(s.last_name || ' ' || s.first_name, f.name, 'Famille') student_name,
             CASE WHEN p.family_id IS NOT NULL THEN 1 ELSE 0 END is_family,
             COALESCE((SELECT SUM(pr.amount) FROM payment_refunds pr WHERE pr.payment_id=p.id),0) refunded_amount
      FROM payments p
      LEFT JOIN students s ON s.id = p.student_id
      LEFT JOIN families f ON f.id = p.family_id
      WHERE p.status = 'posted'
      ORDER BY p.paid_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(_paymentFromRow).toList();
  }

  Future<List<PaymentItem>> cancelledPayments({int limit = 100}) async {
    final rows = await _database.db.rawQuery('''
      SELECT p.*, COALESCE(s.last_name || ' ' || s.first_name, f.name, 'Famille') student_name,
             CASE WHEN p.family_id IS NOT NULL THEN 1 ELSE 0 END is_family,
             COALESCE((SELECT SUM(pr.amount) FROM payment_refunds pr WHERE pr.payment_id=p.id),0) refunded_amount
      FROM payments p
      LEFT JOIN students s ON s.id = p.student_id
      LEFT JOIN families f ON f.id = p.family_id
      WHERE p.status = 'annule'
      ORDER BY p.cancelled_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(_paymentFromRow).toList();
  }

  PaymentItem _paymentFromRow(Map<String, Object?> r) => PaymentItem(
        id: r['id'] as String,
        receiptNumber: r['receipt_number'] as String,
        studentName: r['student_name'] as String,
        amount: r['amount'] as int,
        method: r['payment_method'] as String,
        paidAt: DateTime.parse(r['paid_at'] as String),
        note: r['note'] as String?,
        status: r['status'] as String,
        cancelReason: r['cancel_reason'] as String?,
        isFamilyPayment: (r['is_family'] as int) == 1,
        refundedAmount: (r['refunded_amount'] as int?) ?? 0,
      );

  Future<RecoverySummary> recovery() async {
    final yearId = await _activeSchoolYearId(_database.db);
    final r = (await _database.db.rawQuery(
      'SELECT COALESCE(SUM(amount_due),0) expected, COALESCE(SUM(amount_paid),0) collected FROM dues ${yearId == null ? '' : 'WHERE school_year_id = ?'}',
      yearId == null ? null : [yearId],
    )).first;
    final e = r['expected'] as int;
    final p = r['collected'] as int;
    return RecoverySummary(expected: e, collected: p, outstanding: e - p);
  }

  // --- Forfaits --------------------------------------------------------

  Future<void> createPackage({required String type, required String feeId, String? studentId, String? familyId, required int amount, String? reason, required DateTime validFrom, DateTime? validTo}) async {
    _requireDirector();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Le montant doit être positif');
    if (type != 'individual' && type != 'family') throw ArgumentError('Type de forfait invalide.');
    if (type == 'individual' && studentId == null) throw ArgumentError('studentId requis pour un forfait individuel');
    if (type == 'family' && familyId == null) throw ArgumentError('familyId requis pour un forfait familial');
    if (validTo != null && validTo.isBefore(validFrom)) throw ArgumentError('La date de fin doit être postérieure à la date de début');

    final db = _database.db;
    final feeExists = firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM fee_categories WHERE id = ? AND active = 1',
          [feeId],
        )) ??
        0;
    if (feeExists == 0) throw StateError('Rubrique introuvable ou désactivée.');

    if (type == 'individual') {
      final studentRows = await db.rawQuery(
        "SELECT family_id FROM students WHERE id = ? AND status IN ('active','reinscrit') LIMIT 1",
        [studentId],
      );
      if (studentRows.isEmpty) throw StateError('Élève introuvable ou inactif.');
      final studentFamilyId = studentRows.first['family_id'] as String?;
      if (studentFamilyId != null) {
        final conflictingFamilyPackage = firstIntValue(await db.rawQuery('''
          SELECT COUNT(*) FROM packages
          WHERE active = 1 AND type = 'family' AND family_id = ? AND fee_id = ?
            AND valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)
        ''', [studentFamilyId, feeId, (validTo ?? DateTime(9999, 12, 31)).toIso8601String(), validFrom.toIso8601String()])) ?? 0;
        if (conflictingFamilyPackage > 0) {
          throw StateError('Un forfait familial actif couvre déjà cette rubrique et cette période. Désactivez-le avant de créer un forfait individuel.');
        }
      }
    } else {
      final members = firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM students WHERE family_id = ? AND status IN ('active','reinscrit')",
            [familyId],
          )) ??
          0;
      if (members == 0) throw StateError('Cette famille ne contient aucun élève actif.');
      final conflictingIndividualPackage = firstIntValue(await db.rawQuery('''
        SELECT COUNT(*) FROM packages p
        JOIN students s ON s.id = p.student_id
        WHERE p.active = 1 AND p.type = 'individual' AND s.family_id = ? AND p.fee_id = ?
          AND p.valid_from <= ? AND (p.valid_to IS NULL OR p.valid_to >= ?)
      ''', [familyId, feeId, (validTo ?? DateTime(9999, 12, 31)).toIso8601String(), validFrom.toIso8601String()])) ?? 0;
      if (conflictingIndividualPackage > 0) {
        throw StateError('Un forfait individuel actif existe déjà pour un élève de cette famille sur cette rubrique et cette période. Désactivez-le avant de créer le forfait familial.');
      }
    }

    // En release candidate, on évite de modifier rétroactivement des dettes
    // déjà générées. Le forfait doit être créé avant les échéances auxquelles
    // il doit s'appliquer. Cela préserve les montants déjà encaissés/audités.
    final validityStart = validFrom.toIso8601String();
    final validityEnd = validTo?.toIso8601String();
    final targetClause = type == 'individual' ? 'student_id = ?' : 'family_id = ?';
    final targetId = type == 'individual' ? studentId : familyId;
    final existingDues = firstIntValue(await db.rawQuery(
          '''SELECT COUNT(*) FROM dues
             WHERE $targetClause AND fee_id = ?
               AND COALESCE(due_date, created_at) >= ?
               AND (? IS NULL OR COALESCE(due_date, created_at) <= ?)''',
          [targetId, feeId, validityStart, validityEnd, validityEnd],
        )) ??
        0;
    if (existingDues > 0) {
      throw StateError('Des échéances existent déjà pour cette rubrique et cette période. Créez le forfait avant de générer les échéances concernées.');
    }

    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await db.transaction((txn) async {
      if (type == 'individual') {
        await txn.update('packages', {'active': 0}, where: "type = 'individual' AND student_id = ? AND fee_id = ? AND active = 1", whereArgs: [studentId, feeId]);
      } else {
        await txn.update('packages', {'active': 0}, where: "type = 'family' AND family_id = ? AND fee_id = ? AND active = 1", whereArgs: [familyId, feeId]);
      }
      await txn.insert('packages', {
        'id': id,
        'type': type,
        'student_id': type == 'individual' ? studentId : null,
        'family_id': type == 'family' ? familyId : null,
        'fee_id': feeId,
        'amount': amount,
        'reason': reason,
        'valid_from': validityStart,
        'valid_to': validityEnd,
        'active': 1,
        'created_at': now,
      });
      await txn.insert('audit_log', {
        'entity_type': 'package',
        'entity_id': id,
        'action': 'create',
        'new_value': '$type/$feeId/$studentId/$familyId/$amount',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<void> deactivatePackage(String packageId) async {
    _requireDirector();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('packages', where: 'id = ?', whereArgs: [packageId], limit: 1);
      if (rows.isEmpty) throw StateError('Forfait introuvable.');
      if ((rows.first['active'] as int) == 0) return;
      await txn.update('packages', {'active': 0}, where: 'id = ?', whereArgs: [packageId]);
      await txn.insert('audit_log', {
        'entity_type': 'package',
        'entity_id': packageId,
        'action': 'deactivate',
        'old_value': '${rows.first['type']}/${rows.first['amount']}',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
  }

  Future<List<PackageItem>> packages() async {
    final rows = await _database.db.rawQuery('''
      SELECT p.*, COALESCE(s.last_name || ' ' || s.first_name, fam.name, '—') beneficiary,
             COALESCE(fc.name, 'Rubrique à reconfigurer') fee_name
      FROM packages p
      LEFT JOIN students s ON s.id = p.student_id
      LEFT JOIN families fam ON fam.id = p.family_id
      LEFT JOIN fee_categories fc ON fc.id = p.fee_id
      ORDER BY p.created_at DESC
    ''');
    return rows
        .map((r) => PackageItem(
              id: r['id'] as String,
              type: r['type'] as String,
              beneficiary: r['beneficiary'] as String,
              feeName: r['fee_name'] as String,
              amount: r['amount'] as int,
              validFrom: DateTime.parse(r['valid_from'] as String),
              validTo: r['valid_to'] == null ? null : DateTime.parse(r['valid_to'] as String),
              reason: r['reason'] as String?,
              active: (r['active'] as int) == 1,
            ))
        .toList();
  }
  void _requireDirector() {
    BusinessWriteGuard.ensureAllowed('finance.manage');
  }

  void _requireCollectionPermission() {
    BusinessWriteGuard.ensureAllowed('finance.collect');
    if (OperatorSession.isAuthenticated && !OperatorSession.hasPermission('finance.collect')) {
      throw StateError('Veuillez vous authentifier pour effectuer un encaissement.');
    }
  }

}
