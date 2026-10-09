import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/operator_session.dart';
import '../../core/session/business_write_guard.dart';
import '../models/student.dart';
import '../../services/student_bulk_import_service.dart';
import '../../services/annual_billing_service.dart';

class StudentRepository {
  StudentRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  String _paymentStatusSql() => '''
    CASE
      WHEN billing_state.status = 'pending_configuration' THEN 'pending_configuration'
      WHEN billing_state.status = 'needs_review' THEN 'needs_review'
      WHEN COALESCE(ds.total_due, 0) = 0 THEN 'no_due'
      WHEN COALESCE(ds.balance, 0) <= 0 THEN 'paid'
      WHEN COALESCE(ds.overdue_balance, 0) > 0 THEN 'overdue'
      WHEN COALESCE(ds.total_paid, 0) > 0 THEN 'partial'
      ELSE 'unpaid'
    END
  ''';

  Future<List<Student>> list({StudentFilter filter = const StudentFilter(), int? limit, int offset = 0}) async {
    final activeYear=await _activeSchoolYearId(_database.db);
    final conditions = <String>[];
    final args = <Object?>[];
    final normalized = filter.query.trim();
    if (normalized.isNotEmpty) {
      conditions.add('(s.first_name LIKE ? OR s.last_name LIKE ? OR s.registration_number LIKE ? OR s.guardian_name LIKE ? OR s.guardian_phone LIKE ?)');
      args.addAll(['%$normalized%', '%$normalized%', '%$normalized%', '%$normalized%', '%$normalized%']);
    }
    if (filter.cycleId != null) { conditions.add('cy.id = ?'); args.add(filter.cycleId); }
    if (filter.classroomId != null) { conditions.add('s.classroom_id = ?'); args.add(filter.classroomId); }
    if (filter.familyId != null) { conditions.add('s.family_id = ?'); args.add(filter.familyId); }
    if (filter.status != null) { conditions.add('s.status = ?'); args.add(filter.status); }
    if (filter.paymentStatus != null) {
      if (filter.paymentStatus == 'package') {
        conditions.add('EXISTS (SELECT 1 FROM packages pk WHERE pk.active = 1 AND (pk.student_id = s.id OR (s.family_id IS NOT NULL AND pk.family_id = s.family_id)))');
      } else {
        conditions.add('${_paymentStatusSql()} = ?');
        args.add(filter.paymentStatus);
      }
    }
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await _database.db.rawQuery('''
      SELECT s.*, c.name classroom_name, c.cycle_id cycle_id, cy.name cycle_name,
             fam.name family_name,
             ${_paymentStatusSql()} payment_status,
             CASE WHEN EXISTS (SELECT 1 FROM packages pk WHERE pk.active = 1 AND (pk.student_id = s.id OR (s.family_id IS NOT NULL AND pk.family_id = s.family_id))) THEN 1 ELSE 0 END has_package
      FROM students s
      JOIN classrooms c ON c.id = s.classroom_id
      JOIN cycles cy ON cy.id = c.cycle_id
      LEFT JOIN families fam ON fam.id = s.family_id
      LEFT JOIN (
        SELECT student_id,
               SUM(amount_due) total_due,
               SUM(amount_paid) total_paid,
               SUM(amount_due - amount_paid) balance,
               SUM(CASE WHEN status != 'paid' AND due_date IS NOT NULL AND due_date < ? THEN amount_due - amount_paid ELSE 0 END) overdue_balance
        FROM dues
        WHERE (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))
          ${activeYear == null ? '' : 'AND school_year_id = ?'}
        GROUP BY student_id
      ) ds ON ds.student_id = s.id
      LEFT JOIN student_billing_state billing_state ON billing_state.student_id=s.id
        AND billing_state.school_year_id=(SELECT id FROM school_years WHERE is_active=1 LIMIT 1)
      $where
      ORDER BY s.last_name COLLATE NOCASE, s.first_name COLLATE NOCASE
      ${limit == null ? '' : 'LIMIT ? OFFSET ?'}
    ''', [DateTime.now().toIso8601String(), if(activeYear!=null) activeYear, ...args, if(limit!=null) limit, if(limit!=null) offset]);
    return rows.map(Student.fromMap).toList();
  }

  Future<String?> studentIdForDue(String dueId) async {
    final rows=await _database.db.query('dues',columns:['student_id'],where:'id=?',whereArgs:[dueId],limit:1);
    return rows.isEmpty?null:rows.first['student_id'] as String?;
  }

  Future<Student> detail(String studentId) async {
    final activeYear=await _activeSchoolYearId(_database.db);
    final rows = await _database.db.rawQuery('''
      SELECT s.*, c.name classroom_name, c.cycle_id cycle_id, cy.name cycle_name,
             fam.name family_name,
             ${_paymentStatusSql()} payment_status,
             CASE WHEN EXISTS (SELECT 1 FROM packages pk WHERE pk.active = 1 AND (pk.student_id = s.id OR (s.family_id IS NOT NULL AND pk.family_id = s.family_id))) THEN 1 ELSE 0 END has_package
      FROM students s
      JOIN classrooms c ON c.id = s.classroom_id
      JOIN cycles cy ON cy.id = c.cycle_id
      LEFT JOIN families fam ON fam.id = s.family_id
      LEFT JOIN (
        SELECT student_id, SUM(amount_due) total_due, SUM(amount_paid) total_paid,
               SUM(amount_due - amount_paid) balance,
               SUM(CASE WHEN status != 'paid' AND due_date IS NOT NULL AND due_date < ? THEN amount_due - amount_paid ELSE 0 END) overdue_balance
        FROM dues
        WHERE (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type = 'family'))
          ${activeYear == null ? '' : 'AND school_year_id = ?'}
        GROUP BY student_id
      ) ds ON ds.student_id = s.id
      LEFT JOIN student_billing_state billing_state ON billing_state.student_id=s.id
        AND billing_state.school_year_id=(SELECT id FROM school_years WHERE is_active=1 LIMIT 1)
      WHERE s.id = ? LIMIT 1
    ''', [DateTime.now().toIso8601String(), if(activeYear!=null) activeYear, studentId]);
    if (rows.isEmpty) throw StateError('Élève introuvable.');
    return Student.fromMap(rows.first);
  }

  Future<List<ClassroomOption>> classrooms({bool includeInactive = false}) async {
    final activeYear=await _activeSchoolYearId(_database.db);
    final classroomWhere = includeInactive ? '' : 'WHERE c.active = 1';
    final rows = activeYear == null
      ? await _database.db.rawQuery('''
          SELECT c.id, c.cycle_id, c.name, c.capacity, c.active, cy.name cycle_name,
                 SUM(CASE WHEN s.status IN ('active','reinscrit') THEN 1 ELSE 0 END) current_count
          FROM classrooms c JOIN cycles cy ON cy.id = c.cycle_id
          LEFT JOIN students s ON s.classroom_id = c.id
          $classroomWhere
          GROUP BY c.id, c.cycle_id, c.name, c.capacity, c.active, cy.name, cy.sort_order
          ORDER BY cy.sort_order, c.name
        ''')
      : await _database.db.rawQuery('''
          SELECT c.id, c.cycle_id, c.name, c.capacity, c.active, cy.name cycle_name,
                 COUNT(se.student_id) current_count
          FROM classrooms c JOIN cycles cy ON cy.id = c.cycle_id
          LEFT JOIN student_enrollments se
            ON se.classroom_id=c.id AND se.school_year_id=? AND se.status='active'
          $classroomWhere
          GROUP BY c.id, c.cycle_id, c.name, c.capacity, c.active, cy.name, cy.sort_order
          ORDER BY cy.sort_order, c.name
        ''',[activeYear]);
    return rows.map((row) => ClassroomOption(
      id: row['id'] as String, cycleId: row['cycle_id'] as String, name: row['name'] as String,
      cycleName: row['cycle_name'] as String, capacity: row['capacity'] as int?, currentCount: row['current_count'] as int? ?? 0,
      active: (row['active'] as int? ?? 1) == 1,
    )).toList();
  }

  Future<String> add({
    required String firstName, required String lastName, required String classroomId,
    String? guardianName, String? guardianPhone, String? familyId, String? gender,
    DateTime? birthDate, String? birthPlace, String? nationality, String? address, String? originSchool,
  }) async {
    _requireManagePermission();
    final first = firstName.trim(); final last = lastName.trim();
    if (first.isEmpty) throw ArgumentError('Le prénom de l’élève est obligatoire.');
    if (last.isEmpty) throw ArgumentError('Le nom de l’élève est obligatoire.');
    final now = DateTime.now(); final id = _uuid.v4();
    await _database.db.transaction((txn) async {
      await _ensureClassroomCapacity(txn, classroomId);
      final registration = await _nextRegistrationNumber(txn, now.year);
      await txn.insert('students', {
        'id': id, 'classroom_id': classroomId, 'family_id': familyId, 'registration_number': registration,
        'first_name': first, 'last_name': last, 'guardian_name': guardianName?.trim(), 'guardian_phone': guardianPhone?.trim(),
        'gender': gender, 'birth_date': birthDate?.toIso8601String(), 'birth_place': birthPlace?.trim(), 'nationality':nationality?.trim(), 'address':address?.trim(), 'origin_school':originSchool?.trim(),
        'status': 'active', 'enrollment_date': now.toIso8601String(), 'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(),
      });
      if((guardianName??'').trim().isNotEmpty) await txn.insert('student_guardians',{'id':_uuid.v4(),'student_id':id,'name':guardianName!.trim(),'phone':guardianPhone?.trim(),'relationship':'tuteur','is_primary':1,'is_financial':1,'is_emergency':1,'created_at':now.toIso8601String()});
      await txn.insert('student_status_history', {'id': _uuid.v4(), 'student_id': id, 'old_status': null, 'new_status': 'active', 'changed_at': now.toIso8601String(), 'note': 'Inscription initiale'});
      final schoolYearId = await _activeSchoolYearId(txn);
      if (schoolYearId != null) {
        await txn.insert('student_enrollments', {
          'id': _uuid.v4(),
          'student_id': id,
          'school_year_id': schoolYearId,
          'classroom_id': classroomId,
          'enrollment_type': 'new',
          'status': 'active',
          'effective_from': now.toIso8601String(),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        await const AnnualBillingService().createForEnrollment(txn,
          studentId: id, schoolYearId: schoolYearId,
          classroomId: classroomId, enrolledAt: now);
      }
      await _audit(txn, 'student', id, 'create', registration);
    });
    return id;
  }


  Future<StudentBulkImportPreview> previewBulkImport(List<StudentImportRow> rows) async {
    if (rows.isEmpty) return const StudentBulkImportPreview(total: 0, valid: 0, skipped: 0, errors: []);
    final db = _database.db;
    final classroomRows = await db.rawQuery("SELECT c.id,c.name classroom_name,c.capacity,cy.name cycle_name,(SELECT COUNT(*) FROM students s WHERE s.classroom_id=c.id AND s.status IN ('active','reinscrit')) current_count FROM classrooms c JOIN cycles cy ON cy.id=c.cycle_id WHERE c.active=1");
    final lookup=<String,Map<String,Object?>>{};
    for(final c in classroomRows){final name=(c['classroom_name'] as String).trim().toLowerCase();final cycle=(c['cycle_name'] as String).trim().toLowerCase();for(final key in [c['id'].toString().toLowerCase(),name,'$cycle $name','$cycle · $name']){lookup[key]=c;}}
    final projected=<String,int>{}; final errors=<String>[]; final seen=<String>{}; var valid=0;
    for(final row in rows){
      final c=lookup[row.classroom.trim().toLowerCase()];
      if(c==null){errors.add('Ligne ${row.line} : classe « ${row.classroom} » introuvable.');continue;}
      final duplicateKey='${row.firstName.trim().toLowerCase()}|${row.lastName.trim().toLowerCase()}|${row.birthDate?.toIso8601String().split('T').first ?? ''}';
      if(!seen.add(duplicateKey)){errors.add('Ligne ${row.line} : doublon dans le fichier (${row.lastName} ${row.firstName}).');continue;}
      final args=<Object?>[row.firstName.trim(),row.lastName.trim()]; var sql='lower(trim(first_name))=lower(?) AND lower(trim(last_name))=lower(?)';
      if(row.birthDate!=null){sql+=' AND date(birth_date)=date(?)';args.add(row.birthDate!.toIso8601String());}
      final duplicate=firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM students WHERE $sql',args)) ?? 0;
      if(duplicate>0){errors.add('Ligne ${row.line} : doublon probable déjà présent (${row.lastName} ${row.firstName}).');continue;}
      final id=c['id'] as String; final current=c['current_count'] as int? ?? 0; final capacity=c['capacity'] as int?; final added=projected[id]??0;
      if(capacity!=null && capacity>0 && current+added>=capacity){errors.add('Ligne ${row.line} : capacité de ${c['classroom_name']} dépassée ($capacity).');continue;}
      projected[id]=added+1;valid++;
    }
    return StudentBulkImportPreview(total:rows.length,valid:valid,skipped:rows.length-valid,errors:errors);
  }

  Future<StudentBulkImportResult> bulkImport(List<StudentImportRow> rows) async {
    _requireManagePermission();
    final preview=await previewBulkImport(rows);
    if(preview.valid==0) return StudentBulkImportResult(imported:0,skipped:preview.skipped,errors:preview.errors);
    final errorLines=<int>{};final linePattern=RegExp(r'^Ligne (\d+)');
    for(final e in preview.errors){final m=linePattern.firstMatch(e);if(m!=null)errorLines.add(int.parse(m.group(1)!));}
    final validRows=rows.where((r)=>!errorLines.contains(r.line)).toList();final now=DateTime.now();
    await _database.db.transaction((txn) async {
      final classroomRows=await txn.rawQuery("SELECT c.id,c.name classroom_name,cy.name cycle_name FROM classrooms c JOIN cycles cy ON cy.id=c.cycle_id WHERE c.active=1");
      final lookup=<String,String>{};for(final c in classroomRows){final id=c['id'] as String;final name=(c['classroom_name'] as String).trim().toLowerCase();final cycle=(c['cycle_name'] as String).trim().toLowerCase();for(final k in [id.toLowerCase(),name,'$cycle $name','$cycle · $name'])lookup[k]=id;}
      final year=await _activeSchoolYearId(txn);
      for(final row in validRows){
        final classroomId=lookup[row.classroom.trim().toLowerCase()]!;String? familyId;
        if((row.familyName??'').trim().isNotEmpty){final family=await txn.query('families',columns:['id'],where:'lower(trim(name))=lower(?)',whereArgs:[row.familyName!.trim()],limit:1);if(family.isNotEmpty){familyId=family.first['id'] as String;}else{familyId=_uuid.v4();await txn.insert('families',{'id':familyId,'name':row.familyName!.trim(),'primary_phone':row.guardianPhone?.trim(),'address':row.address?.trim(),'created_at':now.toIso8601String()});}}
        final id=_uuid.v4();final registration=await _nextRegistrationNumber(txn,now.year);
        await txn.insert('students',{'id':id,'classroom_id':classroomId,'family_id':familyId,'registration_number':registration,'first_name':row.firstName.trim(),'last_name':row.lastName.trim(),'guardian_name':row.guardianName?.trim(),'guardian_phone':row.guardianPhone?.trim(),'gender':row.gender,'birth_date':row.birthDate?.toIso8601String(),'birth_place':row.birthPlace?.trim(),'nationality':row.nationality?.trim(),'address':row.address?.trim(),'origin_school':row.originSchool?.trim(),'status':'active','enrollment_date':now.toIso8601String(),'created_at':now.toIso8601String(),'updated_at':now.toIso8601String()});
        if((row.guardianName??'').trim().isNotEmpty) await txn.insert('student_guardians',{'id':_uuid.v4(),'student_id':id,'name':row.guardianName!.trim(),'phone':row.guardianPhone?.trim(),'relationship':'tuteur','is_primary':1,'is_financial':1,'is_emergency':1,'created_at':now.toIso8601String()});
        await txn.insert('student_status_history',{'id':_uuid.v4(),'student_id':id,'old_status':null,'new_status':'active','changed_at':now.toIso8601String(),'note':'Import massif transactionnel'});
        if(year!=null) {
          await txn.insert('student_enrollments',{'id':_uuid.v4(),'student_id':id,'school_year_id':year,'classroom_id':classroomId,'enrollment_type':'new','status':'active','effective_from':now.toIso8601String(),'created_at':now.toIso8601String(),'updated_at':now.toIso8601String()});
          await const AnnualBillingService().createForEnrollment(txn,
            studentId: id, schoolYearId: year,
            classroomId: classroomId, enrolledAt: now);
        }
      }
      await _audit(txn,'student_import',now.millisecondsSinceEpoch.toString(),'bulk_import_transactional','imported=${validRows.length}/skipped=${preview.skipped}');
    });
    return StudentBulkImportResult(imported:validRows.length,skipped:preview.skipped,errors:preview.errors);
  }


  Future<List<Student>> findPossibleDuplicates({required String firstName, required String lastName, DateTime? birthDate, String? excludingId}) async {
    final where = <String>["lower(trim(first_name)) = lower(?)", "lower(trim(last_name)) = lower(?)"];
    final args = <Object?>[firstName.trim(), lastName.trim()];
    if (birthDate != null) { where.add('date(birth_date) = date(?)'); args.add(birthDate.toIso8601String()); }
    if (excludingId != null) { where.add('id != ?'); args.add(excludingId); }
    final rows = await _database.db.rawQuery("SELECT s.*, c.name classroom_name, c.cycle_id cycle_id, cy.name cycle_name, fam.name family_name, 'no_due' payment_status, 0 has_package FROM students s JOIN classrooms c ON c.id=s.classroom_id JOIN cycles cy ON cy.id=c.cycle_id LEFT JOIN families fam ON fam.id=s.family_id WHERE ${where.join(' AND ')} LIMIT 10", args);
    return rows.map(Student.fromMap).toList();
  }

  Future<void> updateStudent({required String studentId, required String firstName, required String lastName, required String classroomId, String? guardianName, String? guardianPhone, String? familyId, String? gender, DateTime? birthDate, String? birthPlace, String? nationality, String? address, String? originSchool}) async {
    _requireManagePermission();
    final first=firstName.trim(), last=lastName.trim();
    if(first.isEmpty || last.isEmpty) throw ArgumentError('Nom et prénom obligatoires.');
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final old=await txn.query('students',where:'id = ?',whereArgs:[studentId],limit:1);
      if(old.isEmpty) throw StateError('Élève introuvable.');
      if(old.first['classroom_id'] != classroomId) await _ensureClassroomCapacity(txn,classroomId,excludingStudentId:studentId);
      await txn.update('students', {'first_name':first,'last_name':last,'classroom_id':classroomId,'family_id':familyId,'guardian_name':guardianName?.trim(),'guardian_phone':guardianPhone?.trim(),'gender':gender,'birth_date':birthDate?.toIso8601String(),'birth_place':birthPlace?.trim(),'nationality':nationality?.trim(),'address':address?.trim(),'origin_school':originSchool?.trim(),'updated_at':now}, where:'id = ?',whereArgs:[studentId]);
      final year=await _activeSchoolYearId(txn);
      if(year!=null) {
        await txn.update('student_enrollments',{'classroom_id':classroomId,'updated_at':now},where:'student_id = ? AND school_year_id = ?',whereArgs:[studentId,year]);
        if(old.first['classroom_id'] != classroomId || old.first['family_id'] != familyId) {
          await txn.update('student_billing_state',
            {'status':'needs_review','details':'Classe ou famille modifiée : vérifier les échéances futures.','updated_at':now},
            where:'student_id=? AND school_year_id=?',whereArgs:[studentId,year]);
        }
      }
      await txn.delete('student_guardians',where:'student_id = ? AND is_primary = 1',whereArgs:[studentId]);
      if((guardianName??'').trim().isNotEmpty) await txn.insert('student_guardians',{'id':_uuid.v4(),'student_id':studentId,'name':guardianName!.trim(),'phone':guardianPhone?.trim(),'relationship':'tuteur','is_primary':1,'is_financial':1,'is_emergency':1,'created_at':now});
      await _audit(txn,'student',studentId,'update_identity','${old.first['last_name']} ${old.first['first_name']} -> $last $first');
    });
  }

  Future<String> _nextRegistrationNumber(Transaction txn, int year) async {
    final key = 'student_registration_seq_$year';
    final rows = await txn.query('app_settings', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    var current = rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
    if (current == 0) {
      final existing = await txn.rawQuery('SELECT registration_number FROM students WHERE registration_number LIKE ? ORDER BY registration_number DESC LIMIT 1', ['EL-$year-%']);
      if (existing.isNotEmpty) current = int.tryParse((existing.first['registration_number'] as String? ?? '').split('-').last) ?? 0;
    }
    final next = current + 1; final now = DateTime.now().toIso8601String();
    await txn.insert('app_settings', {'key': key, 'value': next.toString(), 'updated_at': now}, conflictAlgorithm: ConflictAlgorithm.replace);
    return 'EL-$year-${next.toString().padLeft(5, '0')}';
  }

  Future<void> _ensureClassroomCapacity(DatabaseExecutor db, String classroomId, {String? excludingStudentId}) async {
    final rows = await db.rawQuery('''
      SELECT c.capacity, (SELECT COUNT(*) FROM students s WHERE s.classroom_id = c.id AND s.status IN ('active','reinscrit') AND (? IS NULL OR s.id != ?)) current_count
      FROM classrooms c WHERE c.id = ? AND c.active = 1 LIMIT 1
    ''', [excludingStudentId, excludingStudentId, classroomId]);
    if (rows.isEmpty) throw StateError('Classe introuvable ou désactivée.');
    final capacity = rows.first['capacity'] as int?; final current = rows.first['current_count'] as int? ?? 0;
    if (capacity != null && capacity > 0 && current >= capacity) throw StateError('Cette classe a atteint sa capacité maximale ($capacity élèves).');
  }

  /// Réinscrit l'élève dans l'année scolaire active. L'historique des
  /// années précédentes n'est plus écrasé : une ligne `student_enrollments`
  /// distincte est conservée par année scolaire.
  Future<void> reEnroll({required String studentId, required String classroomId}) async {
    _requireManagePermission();
    final now = DateTime.now();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('students', columns: ['status','classroom_id'], where: 'id = ?', whereArgs: [studentId], limit: 1);
      if (rows.isEmpty) throw StateError('Élève introuvable.');
      final schoolYearId = await _activeSchoolYearId(txn);
      if (schoolYearId == null) throw StateError('Aucune année scolaire active. Configurez-la dans Paramètres.');
      await _ensureClassroomCapacity(txn, classroomId, excludingStudentId: studentId);
      final oldStatus = rows.first['status'] as String;
      final oldClassroom = rows.first['classroom_id'] as String;
      final existing = await txn.query('student_enrollments', where: 'student_id = ? AND school_year_id = ?', whereArgs: [studentId, schoolYearId], limit: 1);
      if (existing.isEmpty) {
        await txn.insert('student_enrollments', {
          'id': _uuid.v4(), 'student_id': studentId, 'school_year_id': schoolYearId,
          'classroom_id': classroomId, 'enrollment_type': 're_enrollment', 'status': 'active',
          'effective_from': now.toIso8601String(), 'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(),
        });
      } else {
        await txn.update('student_enrollments', {
          'classroom_id': classroomId, 'status': 'active', 'updated_at': now.toIso8601String(),
          'observations': oldClassroom == classroomId ? 'Réinscription confirmée' : 'Changement de classe pendant l’année active',
        }, where: 'id = ?', whereArgs: [existing.first['id']]);
      }
      // `students` reste le cache de l'état courant pour les modules V4.
      // Le statut métier courant est désormais `active`; le fait qu'il
      // s'agisse d'une réinscription vit dans enrollment_type.
      await txn.update('students', {'classroom_id': classroomId, 'status': 'active', 'updated_at': now.toIso8601String()}, where: 'id = ?', whereArgs: [studentId]);
      await const AnnualBillingService().createForEnrollment(txn,
        studentId: studentId, schoolYearId: schoolYearId,
        classroomId: classroomId, enrolledAt: now);
      await txn.insert('student_status_history', {
        'id': _uuid.v4(), 'student_id': studentId, 'old_status': oldStatus, 'new_status': 'active',
        'changed_at': now.toIso8601String(), 'note': 'Réinscription annuelle',
      });
      await _audit(txn, 'student', studentId, 'reenroll', '$oldStatus/$oldClassroom -> active/$classroomId / year=$schoolYearId');
    });
  }

  /// Changement de classe dans l'année scolaire courante, sans le confondre
  /// avec une réinscription annuelle.
  Future<void> changeClassroom({required String studentId, required String classroomId, String? note}) async {
    _requireManagePermission();
    final now = DateTime.now();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('students', columns: ['classroom_id'], where: 'id = ?', whereArgs: [studentId], limit: 1);
      if (rows.isEmpty) throw StateError('Élève introuvable.');
      final oldClassroom = rows.first['classroom_id'] as String;
      if (oldClassroom == classroomId) return;
      await _ensureClassroomCapacity(txn, classroomId, excludingStudentId: studentId);
      await txn.update('students', {'classroom_id': classroomId, 'updated_at': now.toIso8601String()}, where: 'id = ?', whereArgs: [studentId]);
      final schoolYearId = await _activeSchoolYearId(txn);
      if (schoolYearId != null) {
        await txn.update('student_enrollments', {
          'classroom_id': classroomId,
          'observations': note?.trim().isNotEmpty == true ? note!.trim() : 'Changement de classe',
          'updated_at': now.toIso8601String(),
        }, where: 'student_id = ? AND school_year_id = ?', whereArgs: [studentId, schoolYearId]);
        await txn.update('student_billing_state',
          {'status':'needs_review','details':'Changement de classe : réconciliation financière requise.','updated_at':now.toIso8601String()},
          where:'student_id=? AND school_year_id=?',whereArgs:[studentId,schoolYearId]);
        await txn.insert('student_class_movements', {
          'id':_uuid.v4(),'student_id':studentId,'school_year_id':schoolYearId,
          'from_classroom_id':oldClassroom,'to_classroom_id':classroomId,
          'effective_at':now.toIso8601String(),'reason':note?.trim(),
          'operator_id':OperatorSession.userId,'created_at':now.toIso8601String(),
        });
      }
      await _audit(txn, 'student', studentId, 'classroom_change', '$oldClassroom -> $classroomId${note == null ? '' : ' / $note'}');
    });
  }

  Future<void> updateStatus(String studentId, String status, {String? note}) async {
    _requireManagePermission();
    const allowed = {'active','reinscrit','transfere','exclu','abandon'};
    if (!allowed.contains(status)) throw ArgumentError.value(status, 'status', 'Statut non autorisé');
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('students', columns: ['status'], where: 'id = ?', whereArgs: [studentId], limit: 1);
      if (rows.isEmpty) return; final oldStatus = rows.first['status'] as String; if (oldStatus == status) return;
      final normalizedStatus = status == 'reinscrit' ? 'active' : status;
      await txn.update('students', {'status': normalizedStatus, 'updated_at': now}, where: 'id = ?', whereArgs: [studentId]);
      final schoolYearId = await _activeSchoolYearId(txn);
      if (schoolYearId != null) {
        await txn.update('student_enrollments', {
          'status': normalizedStatus,
          'effective_to': {'transfere','exclu','abandon'}.contains(normalizedStatus) ? now : null,
          'observations': note?.trim(),
          'updated_at': now,
        }, where: 'student_id = ? AND school_year_id = ?', whereArgs: [studentId, schoolYearId]);
      }
      if(schoolYearId!=null && {'transfere','exclu','abandon'}.contains(normalizedStatus)) {
        await txn.update('student_billing_state',
          {'status':'needs_review','details':'Départ de l’élève : traitement manuel des échéances futures requis.','updated_at':now},
          where:'student_id=? AND school_year_id=?',whereArgs:[studentId,schoolYearId]);
      }
      await txn.insert('student_status_history', {'id': _uuid.v4(), 'student_id': studentId, 'old_status': oldStatus, 'new_status': normalizedStatus, 'changed_at': now, 'note': note?.trim()});
      await _audit(txn, 'student', studentId, 'status_change', '$oldStatus -> $status${note == null ? '' : ' / $note'}');
    });
  }

  Future<void> updatePhotoPath(String studentId, String path) async {
    _requireManagePermission();
    await _database.db.update('students', {'photo_path': path, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [studentId]);
    await _database.db.insert('audit_log', {'entity_type':'student','entity_id':studentId,'action':'photo_update','new_value':path,'operator_name':OperatorSession.current,'operator_id':OperatorSession.userId,'operator_role':OperatorSession.role,'created_at':DateTime.now().toIso8601String()});
  }

  Future<List<Map<String,Object?>>> classroomMovements(String studentId) => _database.db.rawQuery('''
    SELECT m.*,sy.label school_year,COALESCE(fc.name,'—') from_classroom,tc.name to_classroom
    FROM student_class_movements m JOIN school_years sy ON sy.id=m.school_year_id
    LEFT JOIN classrooms fc ON fc.id=m.from_classroom_id JOIN classrooms tc ON tc.id=m.to_classroom_id
    WHERE m.student_id=? ORDER BY m.effective_at DESC
  ''',[studentId]);

  Future<List<Map<String,Object?>>> guardians(String studentId) => _database.db.query('student_guardians', where:'student_id=?', whereArgs:[studentId], orderBy:'is_primary DESC,is_financial DESC,name COLLATE NOCASE');

  Future<void> saveGuardian({String? id, required String studentId, required String name, String? phone, required String relationship, bool isPrimary=false, bool isFinancial=false, bool isEmergency=false}) async {
    _requireManagePermission();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom du responsable est obligatoire.');
    final now = DateTime.now().toIso8601String();
    final guardianId = id ?? _uuid.v4();
    await _database.db.transaction((txn) async {
      var demotingCurrentPrimary = false;
      if (id != null) {
        final previous = await txn.query('student_guardians', columns: ['is_primary'], where: 'id=?', whereArgs: [id], limit: 1);
        demotingCurrentPrimary = previous.isNotEmpty && (previous.first['is_primary'] as int? ?? 0) == 1 && !isPrimary;
      }
      if (isPrimary) {
        await txn.update('student_guardians', {'is_primary': 0}, where: 'student_id=?', whereArgs: [studentId]);
      }
      final values = <String, Object?>{
        'student_id': studentId,
        'name': trimmed,
        'phone': phone?.trim(),
        'relationship': relationship.trim().isEmpty ? 'tuteur' : relationship.trim(),
        'is_primary': isPrimary ? 1 : 0,
        'is_financial': isFinancial ? 1 : 0,
        'is_emergency': isEmergency ? 1 : 0,
      };
      if (id == null) {
        await txn.insert('student_guardians', {'id': guardianId, ...values, 'created_at': now});
      } else {
        await txn.update('student_guardians', values, where: 'id=?', whereArgs: [id]);
      }
      await _synchronizePrimaryGuardian(
        txn,
        studentId,
        preferredGuardianId: isPrimary ? guardianId : null,
        avoidGuardianId: demotingCurrentPrimary ? guardianId : null,
      );
      await _audit(txn, 'student_guardian', guardianId, id == null ? 'create' : 'update', '$studentId/$trimmed');
    });
  }

  Future<void> deleteGuardian(String id) async {
    _requireManagePermission();
    final rows = await _database.db.query('student_guardians', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final studentId = rows.first['student_id'] as String;
    await _database.db.transaction((txn) async {
      await txn.delete('student_guardians', where: 'id=?', whereArgs: [id]);
      await _synchronizePrimaryGuardian(txn, studentId);
      await _audit(txn, 'student_guardian', id, 'delete', '$studentId/${rows.first['name']}');
    });
  }

  Future<void> _synchronizePrimaryGuardian(
    DatabaseExecutor db,
    String studentId, {
    String? preferredGuardianId,
    String? avoidGuardianId,
  }) async {
    final guardians = await db.query(
      'student_guardians',
      where: 'student_id=?',
      whereArgs: [studentId],
      orderBy: 'is_primary DESC, created_at ASC, name COLLATE NOCASE',
    );
    if (guardians.isEmpty) {
      await db.update(
        'students',
        {'guardian_name': null, 'guardian_phone': null, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id=?',
        whereArgs: [studentId],
      );
      return;
    }

    Map<String, Object?>? primary;
    if (preferredGuardianId != null) {
      final preferred = guardians.where((row) => row['id'] == preferredGuardianId).toList();
      if (preferred.isNotEmpty) primary = preferred.first;
    }
    primary ??= guardians.cast<Map<String, Object?>>().firstWhere(
          (row) => (row['is_primary'] as int? ?? 0) == 1 && row['id'] != avoidGuardianId,
          orElse: () {
            final alternatives = guardians.where((row) => row['id'] != avoidGuardianId).toList();
            return alternatives.isNotEmpty ? alternatives.first : guardians.first;
          },
        );
    final primaryId = primary['id'] as String;
    await db.update('student_guardians', {'is_primary': 0}, where: 'student_id=? AND id<>?', whereArgs: [studentId, primaryId]);
    await db.update('student_guardians', {'is_primary': 1}, where: 'id=?', whereArgs: [primaryId]);
    await db.update(
      'students',
      {
        'guardian_name': primary['name'] as String,
        'guardian_phone': primary['phone'] as String?,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [studentId],
    );
  }

  Future<Map<String,Object?>> documentCompleteness(String studentId) async {final requirements=await _database.db.query('document_requirements',where:'active=1 AND required=1',orderBy:'sort_order,name');final docs=await _database.db.query('student_documents',columns:['document_type'],where:'student_id=?',whereArgs:[studentId]);final present=docs.map((r)=>(r['document_type'] as String).trim().toLowerCase()).toSet();final missing=requirements.where((r)=>!present.contains((r['name'] as String).trim().toLowerCase())).map((r)=>r['name'] as String).toList();return {'required':requirements.length,'present':requirements.length-missing.length,'missing':missing,'complete':missing.isEmpty};}

  Future<void> addDocument({required String studentId, required String documentType, required String filePath, bool isRequired = false}) async {
    _requireManagePermission();
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    final raw = id.replaceAll('-', '').toUpperCase();
    final verificationCode = 'DOC-${raw.substring(0, raw.length >= 12 ? 12 : raw.length)}';
    await _database.db.transaction((txn) async {
      await txn.insert('student_documents', {
        'id': id,
        'student_id': studentId,
        'document_type': documentType.trim(),
        'file_path': filePath,
        'is_required': isRequired ? 1 : 0,
        'verification_code': verificationCode,
        'verification_status': 'valid',
        'added_at': now,
      });
      await _audit(txn, 'student_document', id, 'create', '$studentId/$documentType/$verificationCode');
    });
  }

  Future<void> deleteDocument(String documentId) async {
    _requireManagePermission();
    final rows = await _database.db.query('student_documents', where: 'id = ?', whereArgs: [documentId], limit: 1);
    if (rows.isEmpty) return;
    await _database.db.transaction((txn) async {
      await txn.delete('student_documents', where: 'id = ?', whereArgs: [documentId]);
      await _audit(txn, 'student_document', documentId, 'delete', '${rows.first['document_type']}');
    });
  }

  Future<List<StudentDocumentItem>> documents(String studentId) async {
    final rows = await _database.db.query('student_documents', where: 'student_id = ?', whereArgs: [studentId], orderBy: 'added_at DESC');
    return rows.map((r) => StudentDocumentItem(
      id: r['id'] as String,
      documentType: r['document_type'] as String,
      filePath: r['file_path'] as String,
      isRequired: (r['is_required'] as int) == 1,
      addedAt: DateTime.parse(r['added_at'] as String),
      verificationCode: r['verification_code'] as String?,
      verificationStatus: (r['verification_status'] as String?) ?? 'valid',
    )).toList();
  }

  Future<Map<String, Object?>?> verifyDocumentCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final rows = await _database.db.rawQuery('''
      SELECT sd.id, sd.document_type, sd.verification_code, sd.verification_status,
             sd.added_at, sd.revoked_at, s.registration_number,
             s.last_name, s.first_name, c.name classroom_name, cy.name cycle_name
      FROM student_documents sd
      JOIN students s ON s.id = sd.student_id
      JOIN classrooms c ON c.id = s.classroom_id
      JOIN cycles cy ON cy.id = c.cycle_id
      WHERE upper(sd.verification_code) = ?
      LIMIT 1
    ''', [normalized]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> revokeDocument(String documentId) async {
    _requireManagePermission();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final changed = await txn.update('student_documents', {
        'verification_status': 'revoked',
        'revoked_at': now,
      }, where: 'id = ?', whereArgs: [documentId]);
      if (changed == 0) throw StateError('Document introuvable.');
      await _audit(txn, 'student_document', documentId, 'revoke', 'Document invalidé');
    });
  }

  Future<List<StudentStatusHistoryItem>> statusHistory(String studentId) async {
    final rows = await _database.db.query('student_status_history', where: 'student_id = ?', whereArgs: [studentId], orderBy: 'changed_at DESC');
    return rows.map((r) => StudentStatusHistoryItem(oldStatus:r['old_status'] as String?, newStatus:r['new_status'] as String, changedAt:DateTime.parse(r['changed_at'] as String), note:r['note'] as String?)).toList();
  }

  Future<StudentFinancialSnapshot> financialSnapshot(String studentId) async {
    final activeYear=await _activeSchoolYearId(_database.db);
    final row = (await _database.db.rawQuery('''
      SELECT COALESCE(SUM(amount_due),0) expected, COALESCE(SUM(amount_paid),0) paid,
             COALESCE(SUM(amount_due-amount_paid),0) outstanding,
             COALESCE(SUM(CASE WHEN status != 'paid' AND due_date IS NOT NULL AND due_date < ? THEN amount_due-amount_paid ELSE 0 END),0) overdue
      FROM dues WHERE student_id = ?
        AND (package_id IS NULL OR package_id NOT IN (SELECT id FROM packages WHERE type='family'))
        ${activeYear == null ? '' : 'AND school_year_id = ?'}
    ''', [DateTime.now().toIso8601String(), studentId, if(activeYear!=null) activeYear])).first;
    final payments = firstIntValue(await _database.db.rawQuery(
      "SELECT COUNT(*) FROM payments WHERE student_id = ? AND status = 'posted' ${activeYear == null ? '' : 'AND school_year_id = ?'}",
      [studentId, if(activeYear!=null) activeYear],
    )) ?? 0;
    return StudentFinancialSnapshot(expected:row['expected'] as int, paid:row['paid'] as int, outstanding:row['outstanding'] as int, overdue:row['overdue'] as int, paymentCount:payments);
  }

  Future<List<StudentDueLine>> dueLines(String studentId) async {
    final activeYear=await _activeSchoolYearId(_database.db);
    final rows = await _database.db.rawQuery('''
      SELECT f.name fee_name, d.period_key, d.amount_due, d.amount_paid, d.status, d.due_date
      FROM dues d JOIN fee_categories f ON f.id = d.fee_id
      WHERE d.student_id = ?
        AND (d.package_id IS NULL OR d.package_id NOT IN (SELECT id FROM packages WHERE type='family'))
        ${activeYear == null ? '' : 'AND d.school_year_id = ?'}
      ORDER BY COALESCE(d.due_date, d.created_at) DESC
    ''', [studentId, if(activeYear!=null) activeYear]);
    return rows.map((r) => StudentDueLine(
      feeName: r['fee_name'] as String, periodKey: r['period_key'] as String,
      amountDue: r['amount_due'] as int, amountPaid: r['amount_paid'] as int,
      status: r['status'] as String, dueDate: r['due_date'] == null ? null : DateTime.parse(r['due_date'] as String),
    )).toList();
  }

  Future<List<StudentPaymentLine>> paymentLines(String studentId) async {
    final activeYear=await _activeSchoolYearId(_database.db);
    final rows = await _database.db.rawQuery('''
      SELECT receipt_number, amount, payment_method, paid_at
      FROM payments WHERE student_id = ? AND status = 'posted'
        ${activeYear == null ? '' : 'AND school_year_id = ?'}
      ORDER BY paid_at DESC
    ''', [studentId, if(activeYear!=null) activeYear]);
    return rows.map((r) => StudentPaymentLine(
      receiptNumber: r['receipt_number'] as String, amount: r['amount'] as int,
      method: r['payment_method'] as String, paidAt: DateTime.parse(r['paid_at'] as String),
    )).toList();
  }

  Future<List<StudentEnrollmentHistoryItem>> enrollmentHistory(String studentId) async {
    final rows = await _database.db.rawQuery('''
      SELECT se.*, sy.label school_year_label, c.name classroom_name, cy.name cycle_name
      FROM student_enrollments se
      JOIN school_years sy ON sy.id = se.school_year_id
      JOIN classrooms c ON c.id = se.classroom_id
      JOIN cycles cy ON cy.id = c.cycle_id
      WHERE se.student_id = ?
      ORDER BY sy.start_date DESC, se.effective_from DESC
    ''', [studentId]);
    return rows.map((r) => StudentEnrollmentHistoryItem(
      schoolYearLabel: r['school_year_label'] as String,
      classroomName: r['classroom_name'] as String,
      cycleName: r['cycle_name'] as String,
      enrollmentType: r['enrollment_type'] as String,
      status: r['status'] as String,
      effectiveFrom: DateTime.parse(r['effective_from'] as String),
      effectiveTo: r['effective_to'] == null ? null : DateTime.tryParse(r['effective_to'] as String),
      observations: r['observations'] as String?,
    )).toList();
  }

  Future<StudentDetailBundle> detailBundle(String studentId) async => StudentDetailBundle(
    student: await detail(studentId), documents: await documents(studentId), history: await statusHistory(studentId), enrollments: await enrollmentHistory(studentId), finance: await financialSnapshot(studentId),
    dues: await dueLines(studentId), payments: await paymentLines(studentId),
  );

  void _requireManagePermission() {
    BusinessWriteGuard.ensureAllowed('Modifier les données élèves');
    if (OperatorSession.isAuthenticated &&
        !OperatorSession.hasPermission('students.manage')) {
      throw StateError('Votre rôle n’autorise pas la modification des élèves.');
    }
  }

  Future<String?> _activeSchoolYearId(DatabaseExecutor db) async {
    final rows = await db.query('school_years', columns: ['id'], where: 'is_active = 1', limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<void> _audit(DatabaseExecutor db, String entityType, String entityId, String action, String newValue) => db.insert('audit_log', {
    'entity_type': entityType, 'entity_id': entityId, 'action': action, 'new_value': newValue,
    'operator_name': OperatorSession.current, 'operator_id': OperatorSession.userId,
    'operator_role': OperatorSession.role, 'created_at': DateTime.now().toIso8601String(),
  });
}
