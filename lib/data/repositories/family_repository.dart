import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import '../models/family.dart';

class FamilyRepository {
  FamilyRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<List<FamilyItem>> list({String query = ''}) async {
    final normalized = query.trim();
    final where = normalized.isEmpty ? '' : 'WHERE f.name LIKE ? OR f.primary_phone LIKE ?';
    final args = normalized.isEmpty ? <Object?>[] : <Object?>['%$normalized%', '%$normalized%'];
    final rows = await _database.db.rawQuery('''
      SELECT f.*, (SELECT COUNT(*) FROM students s WHERE s.family_id = f.id) student_count
      FROM families f
      $where
      ORDER BY f.name COLLATE NOCASE
    ''', args);
    return rows
        .map((r) => FamilyItem(
              id: r['id'] as String,
              name: r['name'] as String,
              primaryPhone: r['primary_phone'] as String?,
              secondaryPhone: r['secondary_phone'] as String?,
              address: r['address'] as String?,
              studentCount: r['student_count'] as int,
            ))
        .toList();
  }

  Future<FamilyItem> add({
    required String name, String? primaryPhone, String? secondaryPhone, String? address}) async {
      BusinessWriteGuard.ensureAllowed('add');
      
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom de la famille est obligatoire.');
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('families', {
        'id': id,
        'name': trimmed,
        'primary_phone': primaryPhone?.trim(),
        'secondary_phone': secondaryPhone?.trim(),
        'address': address?.trim(),
        'created_at': now,
      });
      await txn.insert('audit_log', {
        'entity_type': 'family',
        'entity_id': id,
        'action': 'create',
        'new_value': trimmed,
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
    return FamilyItem(id: id, name: trimmed, primaryPhone: primaryPhone, secondaryPhone: secondaryPhone, address: address);
  }

  Future<void> update({
    required String id,required String name,String? primaryPhone,String? secondaryPhone,String? address}) async {
      BusinessWriteGuard.ensureAllowed('update');
      
    final trimmed=name.trim();if(trimmed.isEmpty)throw ArgumentError('Le nom de la famille est obligatoire.');
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final before=await txn.query('families',where:'id=?',whereArgs:[id],limit:1);if(before.isEmpty)throw StateError('Famille introuvable.');
      await txn.update('families',{'name':trimmed,'primary_phone':primaryPhone?.trim(),'secondary_phone':secondaryPhone?.trim(),'address':address?.trim()},where:'id=?',whereArgs:[id]);
      await txn.insert('audit_log',{'entity_type':'family','entity_id':id,'action':'update','old_value':'${before.first['name']}/${before.first['primary_phone']??''}','new_value':'$trimmed/${primaryPhone?.trim()??''}','operator_name':OperatorSession.current,'operator_id':OperatorSession.userId,'operator_role':OperatorSession.role,'created_at':now});
    });
  }

  Future<List<FamilyMember>> members(String familyId) async {
    final rows = await _database.db.rawQuery('''
      SELECT s.id, s.last_name || ' ' || s.first_name full_name, c.name classroom_name, s.status
      FROM students s
      JOIN classrooms c ON c.id = s.classroom_id
      WHERE s.family_id = ?
      ORDER BY s.last_name COLLATE NOCASE
    ''', [familyId]);
    return rows
        .map((r) => FamilyMember(
              id: r['id'] as String,
              fullName: r['full_name'] as String,
              classroomName: r['classroom_name'] as String,
              status: r['status'] as String,
            ))
        .toList();
  }

  /// Rattache un élève existant à une famille (ou le détache si `familyId` est null).
  Future<void> assignStudent({
    required String studentId, String? familyId}) async {
      BusinessWriteGuard.ensureAllowed('assignStudent');
      
    await _database.db.update(
      'students',
      {'family_id': familyId, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [studentId],
    );
    await _database.db.insert('audit_log', {
      'entity_type': 'student',
      'entity_id': studentId,
      'action': 'family_link',
      'new_value': familyId ?? '(détaché)',
      'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<FamilyBalance> balance(String familyId) async {
    final activeYear=await _database.db.query('school_years',columns:['id'],where:'is_active=1',limit:1);
    final yearId=activeYear.isEmpty?null:activeYear.first['id'] as String?;
    final row = (await _database.db.rawQuery(
      'SELECT COALESCE(SUM(amount_due),0) expected, COALESCE(SUM(amount_paid),0) paid FROM dues WHERE family_id = ? ${yearId == null ? '' : 'AND school_year_id = ?'}',
      yearId == null ? [familyId] : [familyId,yearId],
    )).first;
    return FamilyBalance(expected: row['expected'] as int, paid: row['paid'] as int);
  }
}
