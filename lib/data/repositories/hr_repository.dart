import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import '../models/hr.dart';
import 'cash_rules.dart';

class HrRepository {
  HrRepository(this._database);
  final AppDatabase _database;
  static const _uuid=Uuid();

  Future<void> _audit(DatabaseExecutor db,String type,String id,String action,String value) => db.insert('audit_log',{
    'entity_type':type,'entity_id':id,'action':action,'new_value':value,
    'operator_name':OperatorSession.current,'operator_id':OperatorSession.userId,'operator_role':OperatorSession.role,'created_at':DateTime.now().toIso8601String(),
  });

  Future<HrSummary> summary() async {
    final db=_database.db; final today=DateTime.now(); final day=_dateOnly(today); final in30=_dateOnly(today.add(const Duration(days:30)));
    final active=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM employees WHERE status='active'"))??0;
    final absent=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM attendance_records WHERE attendance_date=? AND status='absent'",[day]))??0;
    final leave=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM leave_requests WHERE status='approved' AND start_date<=? AND end_date>=?",[day,day]))??0;
    final expiring=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM employment_contracts WHERE status='active' AND end_date IS NOT NULL AND end_date>=? AND end_date<=?",[day,in30]))??0;
    final incomplete=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM employees e WHERE e.status='active' AND NOT EXISTS(SELECT 1 FROM employee_documents d WHERE d.employee_id=e.id AND lower(d.document_type) LIKE '%identit%')"))??0;
    final pending=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM payroll_entries WHERE status IN ('draft','validated')"))??0;
    final monthStart=DateTime(today.year,today.month,1).toIso8601String(); final nextMonth=DateTime(today.year,today.month+1,1).toIso8601String();
    final monthly=(firstIntValue(await db.rawQuery("SELECT COALESCE(SUM(net_salary),0) FROM payroll_entries WHERE status='paid' AND paid_at>=? AND paid_at<?",[monthStart,nextMonth]))??0);
    return HrSummary(activeEmployees:active,absentToday:absent,onLeaveToday:leave,expiringContracts:expiring,incompleteFiles:incomplete,pendingPayroll:pending,monthlyPayroll:monthly);
  }

  Future<List<HrDepartment>> departments({bool activeOnly=true}) async {
    final rows=await _database.db.query('hr_departments',where:activeOnly?'active=1':null,orderBy:'name');
    return rows.map((r)=>HrDepartment(id:r['id'] as String,name:r['name'] as String,description:r['description'] as String?,active:(r['active'] as int)==1)).toList();
  }
  Future<void> saveDepartment({
    String? id,required String name,String? description,bool active=true}) async {
      BusinessWriteGuard.ensureAllowed('saveDepartment');
      
    final n=name.trim(); if(n.isEmpty)throw ArgumentError('Le nom du service est obligatoire.'); final now=DateTime.now().toIso8601String(); final key=id??_uuid.v4();
    await _database.db.transaction((txn) async { if(id==null){await txn.insert('hr_departments',{'id':key,'name':n,'description':description?.trim(),'active':active?1:0,'created_at':now,'updated_at':now});}else{await txn.update('hr_departments',{'name':n,'description':description?.trim(),'active':active?1:0,'updated_at':now},where:'id=?',whereArgs:[id]);} await _audit(txn,'hr_department',key,id==null?'create':'update',n);});
  }

  Future<List<HrPosition>> positions({bool activeOnly=true}) async {
    final rows=await _database.db.rawQuery('''SELECT p.*,d.name department_name FROM hr_positions p LEFT JOIN hr_departments d ON d.id=p.department_id ${activeOnly?'WHERE p.active=1':''} ORDER BY p.name''');
    return rows.map((r)=>HrPosition(id:r['id'] as String,name:r['name'] as String,departmentId:r['department_id'] as String?,departmentName:r['department_name'] as String?,description:r['description'] as String?,active:(r['active'] as int)==1)).toList();
  }
  Future<void> savePosition({
    String? id,required String name,String? departmentId,String? description,bool active=true}) async {
      BusinessWriteGuard.ensureAllowed('savePosition');
      
    final n=name.trim(); if(n.isEmpty)throw ArgumentError('Le nom du poste est obligatoire.'); final now=DateTime.now().toIso8601String(); final key=id??_uuid.v4();
    await _database.db.transaction((txn) async {final data={'name':n,'department_id':departmentId,'description':description?.trim(),'active':active?1:0,'updated_at':now};if(id==null){await txn.insert('hr_positions',{'id':key,...data,'created_at':now});}else{await txn.update('hr_positions',data,where:'id=?',whereArgs:[id]);}await _audit(txn,'hr_position',key,id==null?'create':'update',n);});
  }

  Future<List<EmployeeItem>> employees({String query='',String? status,int limit=100,int offset=0}) async {
    final where=<String>[]; final args=<Object?>[]; if(status!=null&&status.isNotEmpty){where.add('e.status=?');args.add(status);} final q=query.trim(); if(q.isNotEmpty){where.add('(e.employee_number LIKE ? OR e.first_name LIKE ? OR e.last_name LIKE ? OR e.phone LIKE ? OR p.name LIKE ? OR d.name LIKE ?)');args.addAll(List.filled(6,'%$q%'));}
    final sql='''SELECT e.*,p.name position_name,d.name department_name FROM employees e LEFT JOIN employee_assignments a ON a.id=(SELECT a2.id FROM employee_assignments a2 WHERE a2.employee_id=e.id AND (a2.end_date IS NULL OR a2.end_date>=date('now')) ORDER BY a2.start_date DESC LIMIT 1) LEFT JOIN hr_positions p ON p.id=a.position_id LEFT JOIN hr_departments d ON d.id=p.department_id ${where.isEmpty?'':'WHERE ${where.join(' AND ')}'} ORDER BY e.last_name,e.first_name LIMIT ? OFFSET ?'''; args.addAll([limit,offset]);
    final rows=await _database.db.rawQuery(sql,args); return rows.map(_employeeFromRow).toList();
  }
  EmployeeItem _employeeFromRow(Map<String,Object?> r)=>EmployeeItem(id:r['id'] as String,employeeNumber:r['employee_number'] as String,firstName:r['first_name'] as String,lastName:r['last_name'] as String,status:r['status'] as String,hireDate:DateTime.parse(r['hire_date'] as String),gender:r['gender'] as String?,phone:r['phone'] as String?,email:r['email'] as String?,address:r['address'] as String?,birthDate:r['birth_date']==null?null:DateTime.tryParse(r['birth_date'] as String),birthPlace:r['birth_place'] as String?,photoPath:r['photo_path'] as String?,idNumber:r['id_number'] as String?,socialSecurityNumber:r['social_security_number'] as String?,emergencyContactName:r['emergency_contact_name'] as String?,emergencyContactPhone:r['emergency_contact_phone'] as String?,positionName:r['position_name'] as String?,departmentName:r['department_name'] as String?);
  Future<EmployeeItem?> employee(String id) async {final rows=await _database.db.rawQuery('''SELECT e.*,p.name position_name,d.name department_name FROM employees e LEFT JOIN employee_assignments a ON a.id=(SELECT a2.id FROM employee_assignments a2 WHERE a2.employee_id=e.id ORDER BY a2.start_date DESC LIMIT 1) LEFT JOIN hr_positions p ON p.id=a.position_id LEFT JOIN hr_departments d ON d.id=p.department_id WHERE e.id=? LIMIT 1''',[id]);return rows.isEmpty?null:_employeeFromRow(rows.first);}
  Future<String> saveEmployee({
    String? id,required String firstName,required String lastName,String? gender,DateTime? birthDate,String? birthPlace,String? phone,String? email,String? address,String? photoPath,String? idNumber,String? socialSecurityNumber,String? emergencyContactName,String? emergencyContactPhone,DateTime? hireDate,String status='active'}) async {
      BusinessWriteGuard.ensureAllowed('saveEmployee');
      
    final first=firstName.trim(),last=lastName.trim();if(first.isEmpty||last.isEmpty)throw ArgumentError('Nom et prénom obligatoires.'); final now=DateTime.now(); final key=id??_uuid.v4();
    await _database.db.transaction((txn) async {String employeeNumber; if(id==null){final count=firstIntValue(await txn.rawQuery("SELECT COUNT(*) FROM employees WHERE substr(employee_number,5,4)=?",[now.year.toString()]))??0;employeeNumber='EMP-${now.year}-${(count+1).toString().padLeft(5,'0')}';}else{final row=await txn.query('employees',columns:['employee_number','status'],where:'id=?',whereArgs:[id],limit:1);if(row.isEmpty)throw StateError('Employé introuvable.');employeeNumber=row.first['employee_number'] as String;}
      final data={'employee_number':employeeNumber,'first_name':first,'last_name':last,'gender':gender,'birth_date':birthDate?.toIso8601String(),'birth_place':birthPlace?.trim(),'phone':phone?.trim(),'email':email?.trim(),'address':address?.trim(),'photo_path':photoPath,'id_number':idNumber?.trim(),'social_security_number':socialSecurityNumber?.trim(),'emergency_contact_name':emergencyContactName?.trim(),'emergency_contact_phone':emergencyContactPhone?.trim(),'hire_date':(hireDate??now).toIso8601String(),'status':status,'updated_at':now.toIso8601String()};
      if(id==null){await txn.insert('employees',{'id':key,...data,'created_at':now.toIso8601String()});await txn.insert('employee_status_history',{'id':_uuid.v4(),'employee_id':key,'old_status':null,'new_status':status,'effective_at':now.toIso8601String(),'reason':'Création de la fiche','operator_id':OperatorSession.userId,'created_at':now.toIso8601String()});}else{final old=(await txn.query('employees',columns:['status'],where:'id=?',whereArgs:[id],limit:1)).first['status'] as String;await txn.update('employees',data,where:'id=?',whereArgs:[id]);if(old!=status){await txn.insert('employee_status_history',{'id':_uuid.v4(),'employee_id':key,'old_status':old,'new_status':status,'effective_at':now.toIso8601String(),'reason':'Modification de statut','operator_id':OperatorSession.userId,'created_at':now.toIso8601String()});}}
      await _audit(txn,'employee',key,id==null?'create':'update','$employeeNumber $last $first');
    }); return key;
  }
  Future<void> updateEmployeePhoto(String employeeId, String? path) async {
    BusinessWriteGuard.ensureAllowed('updateEmployeePhoto');
    await _database.db.update('employees', {'photo_path': path, 'updated_at': DateTime.now().toIso8601String()}, where: 'id=?', whereArgs: [employeeId]);
    await _audit(_database.db, 'employee', employeeId, 'photo_update', path ?? 'removed');
  }

  Future<List<Map<String,Object?>>> employeeStatusHistory(String employeeId) => _database.db.query(
    'employee_status_history',
    where:'employee_id=?',
    whereArgs:[employeeId],
    orderBy:'effective_at DESC',
  );

  Future<List<EmployeeContract>> contracts(String employeeId) async {final rows=await _database.db.rawQuery('''SELECT c.*,p.name position_name FROM employment_contracts c LEFT JOIN hr_positions p ON p.id=c.position_id WHERE c.employee_id=? ORDER BY c.start_date DESC''',[employeeId]);return rows.map((r)=>EmployeeContract(id:r['id'] as String,employeeId:r['employee_id'] as String,contractType:r['contract_type'] as String,startDate:DateTime.parse(r['start_date'] as String),endDate:r['end_date']==null?null:DateTime.tryParse(r['end_date'] as String),baseSalary:r['base_salary'] as int,status:r['status'] as String,positionId:r['position_id'] as String?,positionName:r['position_name'] as String?,documentPath:r['document_path'] as String?,notes:r['notes'] as String?)).toList();}
  Future<void> addContract({
    required String employeeId,required String contractType,required DateTime startDate,DateTime? endDate,required int baseSalary,String? positionId,String? documentPath,String? notes}) async {
      BusinessWriteGuard.ensureAllowed('addContract');
      
    if(baseSalary<0) throw ArgumentError('Salaire invalide.');
    if(endDate != null && endDate.isBefore(startDate)) throw ArgumentError('La date de fin est antérieure au début.');
    final id=_uuid.v4(), now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final previousEnd = startDate.subtract(const Duration(days: 1)).toIso8601String();
      await txn.update(
        'employment_contracts',
        {'end_date': previousEnd, 'updated_at': now},
        where: "employee_id=? AND status='active' AND start_date<? AND (end_date IS NULL OR end_date>=?)",
        whereArgs: [employeeId, startDate.toIso8601String(), startDate.toIso8601String()],
      );
      await txn.insert('employment_contracts',{
        'id':id,'employee_id':employeeId,'contract_type':contractType,'start_date':startDate.toIso8601String(),
        'end_date':endDate?.toIso8601String(),'base_salary':baseSalary,'position_id':positionId,
        'status':'active','document_path':documentPath,'notes':notes?.trim(),'created_at':now,'updated_at':now,
      });
      await _audit(txn,'employment_contract',id,'create','$contractType/$baseSalary');
    });
  }

  Future<List<EmployeeAssignment>> assignments(String employeeId) async {final rows=await _database.db.rawQuery('''SELECT a.*,p.name position_name,d.name department_name FROM employee_assignments a JOIN hr_positions p ON p.id=a.position_id LEFT JOIN hr_departments d ON d.id=p.department_id WHERE a.employee_id=? ORDER BY a.start_date DESC''',[employeeId]);return rows.map((r)=>EmployeeAssignment(id:r['id'] as String,employeeId:r['employee_id'] as String,positionId:r['position_id'] as String,positionName:r['position_name'] as String,departmentName:r['department_name'] as String?,schoolYearId:r['school_year_id'] as String?,startDate:DateTime.parse(r['start_date'] as String),endDate:r['end_date']==null?null:DateTime.tryParse(r['end_date'] as String),notes:r['notes'] as String?)).toList();}
  Future<void> addAssignment({
    required String employeeId,required String positionId,String? schoolYearId,required DateTime startDate,String? notes}) async {
      BusinessWriteGuard.ensureAllowed('addAssignment');
      final id=_uuid.v4(),now=DateTime.now().toIso8601String();await _database.db.transaction((txn)async{await txn.update('employee_assignments',{'end_date':startDate.subtract(const Duration(days:1)).toIso8601String()},where:'employee_id=? AND end_date IS NULL',whereArgs:[employeeId]);await txn.insert('employee_assignments',{'id':id,'employee_id':employeeId,'position_id':positionId,'school_year_id':schoolYearId,'start_date':startDate.toIso8601String(),'end_date':null,'notes':notes?.trim(),'created_at':now});await _audit(txn,'employee_assignment',id,'create',positionId);});}

  Future<List<Map<String,Object?>>> employeeDocuments(String employeeId) => _database.db.query('employee_documents',where:'employee_id=?',whereArgs:[employeeId],orderBy:'added_at DESC');
  Future<void> addEmployeeDocument({
    required String employeeId,required String documentType,required String filePath,DateTime? issuedAt,DateTime? expiresAt,String? documentNumber}) async {
      BusinessWriteGuard.ensureAllowed('addEmployeeDocument');
      final id=_uuid.v4();await _database.db.transaction((txn)async{await txn.insert('employee_documents',{'id':id,'employee_id':employeeId,'document_type':documentType.trim(),'file_path':filePath,'document_number':documentNumber?.trim(),'issued_at':issuedAt?.toIso8601String(),'expires_at':expiresAt?.toIso8601String(),'added_at':DateTime.now().toIso8601String()});await _audit(txn,'employee_document',id,'create',documentType);});}
  Future<void> deleteEmployeeDocument(String id) async {
    BusinessWriteGuard.ensureAllowed('deleteEmployeeDocument');await _database.db.transaction((txn)async{final rows=await txn.query('employee_documents',where:'id=?',whereArgs:[id],limit:1);if(rows.isEmpty)return;await txn.delete('employee_documents',where:'id=?',whereArgs:[id]);await _audit(txn,'employee_document',id,'delete',rows.first['document_type'].toString());});}

  Future<List<AttendanceItem>> attendance(DateTime date) async {final day=_dateOnly(date);final rows=await _database.db.rawQuery('''SELECT a.*,e.last_name||' '||e.first_name employee_name FROM attendance_records a JOIN employees e ON e.id=a.employee_id WHERE a.attendance_date=? ORDER BY e.last_name,e.first_name''',[day]);return rows.map((r)=>AttendanceItem(id:r['id'] as String,employeeId:r['employee_id'] as String,employeeName:r['employee_name'] as String,date:DateTime.parse(r['attendance_date'] as String),status:r['status'] as String,arrivalTime:r['arrival_time'] as String?,departureTime:r['departure_time'] as String?,lateMinutes:(r['late_minutes'] as int?)??0,note:r['note'] as String?)).toList();}
  Future<void> setAttendance({
    required String employeeId,required DateTime date,required String status,String? arrivalTime,String? departureTime,int lateMinutes=0,String? note}) async {
      BusinessWriteGuard.ensureAllowed('setAttendance');
      final day=_dateOnly(date),now=DateTime.now().toIso8601String();await _database.db.transaction((txn)async{final existing=await txn.query('attendance_records',columns:['id'],where:'employee_id=? AND attendance_date=?',whereArgs:[employeeId,day],limit:1);if(existing.isEmpty){await txn.insert('attendance_records',{'id':_uuid.v4(),'employee_id':employeeId,'attendance_date':day,'status':status,'arrival_time':arrivalTime,'departure_time':departureTime,'late_minutes':lateMinutes,'note':note?.trim(),'created_at':now,'updated_at':now});}else{await txn.update('attendance_records',{'status':status,'arrival_time':arrivalTime,'departure_time':departureTime,'late_minutes':lateMinutes,'note':note?.trim(),'updated_at':now},where:'id=?',whereArgs:[existing.first['id']]);}await _audit(txn,'attendance',employeeId,'set','$day/$status');});}

  Future<List<Map<String,Object?>>> leaveTypes({bool activeOnly=true}) => _database.db.query('leave_types',where:activeOnly?'active=1':null,orderBy:'name');
  Future<void> saveLeaveType({
    String? id,required String name,required bool paid,required bool requiresProof,bool active=true}) async {
      BusinessWriteGuard.ensureAllowed('saveLeaveType');
      
    final n=name.trim(); if(n.isEmpty) throw ArgumentError('Le nom du type de congé est obligatoire.');
    final key=id??_uuid.v4();
    await _database.db.transaction((txn) async {
      final data={'name':n,'paid':paid?1:0,'requires_proof':requiresProof?1:0,'active':active?1:0};
      if(id==null){await txn.insert('leave_types',{'id':key,...data});}else{await txn.update('leave_types',data,where:'id=?',whereArgs:[id]);}
      await _audit(txn,'leave_type',key,id==null?'create':'update',n);
    });
  }
  Future<List<LeaveRequestItem>> leaveRequests({String? status}) async {final args=<Object?>[];final where=status==null?'':'WHERE l.status=?';if(status!=null)args.add(status);final rows=await _database.db.rawQuery('''SELECT l.*,e.last_name||' '||e.first_name employee_name,t.name leave_type_name FROM leave_requests l JOIN employees e ON e.id=l.employee_id JOIN leave_types t ON t.id=l.leave_type_id $where ORDER BY l.created_at DESC''',args);return rows.map((r)=>LeaveRequestItem(id:r['id'] as String,employeeId:r['employee_id'] as String,employeeName:r['employee_name'] as String,leaveTypeName:r['leave_type_name'] as String,startDate:DateTime.parse(r['start_date'] as String),endDate:DateTime.parse(r['end_date'] as String),days:r['days'] as int,status:r['status'] as String,reason:r['reason'] as String?,note:r['decision_note'] as String?)).toList();}
  Future<void> requestLeave({
    required String employeeId,required String leaveTypeId,required DateTime startDate,required DateTime endDate,String? reason,String? proofPath}) async {
      BusinessWriteGuard.ensureAllowed('requestLeave');
      if(endDate.isBefore(startDate))throw ArgumentError('La date de fin est antérieure au début.');final days=endDate.difference(startDate).inDays+1,id=_uuid.v4(),now=DateTime.now().toIso8601String();await _database.db.transaction((txn)async{await txn.insert('leave_requests',{'id':id,'employee_id':employeeId,'leave_type_id':leaveTypeId,'start_date':_dateOnly(startDate),'end_date':_dateOnly(endDate),'days':days,'reason':reason?.trim(),'proof_path':proofPath,'status':'pending','requested_at':now,'created_at':now,'updated_at':now});await _audit(txn,'leave_request',id,'submit','$days jours');});}
  Future<void> decideLeave(String id,{
    required bool approve,String? note}) async {
      BusinessWriteGuard.ensureAllowed('decideLeave');
      
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows=await txn.query('leave_requests',where:"id=? AND status='pending'",whereArgs:[id],limit:1);if(rows.isEmpty)throw StateError('Demande introuvable ou déjà traitée.');final leave=rows.first;
      await txn.update('leave_requests',{'status':approve?'approved':'rejected','decided_by':OperatorSession.userId,'decided_at':now,'decision_note':note?.trim(),'updated_at':now},where:'id=?',whereArgs:[id]);
      if(approve){var day=DateTime.parse(leave['start_date'] as String);final end=DateTime.parse(leave['end_date'] as String);while(!day.isAfter(end)){final date=_dateOnly(day);final existing=await txn.query('attendance_records',columns:['id'],where:'employee_id=? AND attendance_date=?',whereArgs:[leave['employee_id'],date],limit:1);final data={'status':'leave','note':'Congé/permission approuvé','updated_at':now};if(existing.isEmpty){await txn.insert('attendance_records',{'id':_uuid.v4(),'employee_id':leave['employee_id'],'attendance_date':date,...data,'created_at':now});}else{await txn.update('attendance_records',data,where:'id=?',whereArgs:[existing.first['id']]);}day=day.add(const Duration(days:1));}}
      await _audit(txn,'leave_request',id,approve?'approve':'reject',note??'');
    });
  }

  Future<List<Map<String,Object?>>> salaryComponents({bool activeOnly=true})=>_database.db.query('salary_components',where:activeOnly?'active=1':null,orderBy:'kind,name');
  Future<void> saveSalaryComponent({
    String? id,required String name,required String kind,required String calculationType,required int value,bool taxable=false,bool active=true}) async {
      BusinessWriteGuard.ensureAllowed('saveSalaryComponent');
      if(!['earning','deduction'].contains(kind))throw ArgumentError('Type invalide.');if(!['fixed','percentage'].contains(calculationType))throw ArgumentError('Calcul invalide.');final key=id??_uuid.v4(),now=DateTime.now().toIso8601String();final data={'name':name.trim(),'kind':kind,'calculation_type':calculationType,'value':value,'taxable':taxable?1:0,'active':active?1:0,'updated_at':now};await _database.db.transaction((txn)async{if(id==null)await txn.insert('salary_components',{'id':key,...data,'created_at':now});else await txn.update('salary_components',data,where:'id=?',whereArgs:[id]);await _audit(txn,'salary_component',key,id==null?'create':'update',name);});}
  Future<List<Map<String,Object?>>> employeeSalaryComponents(String employeeId)=>_database.db.rawQuery('''SELECT esc.*,sc.name,sc.kind,sc.calculation_type FROM employee_salary_components esc JOIN salary_components sc ON sc.id=esc.component_id WHERE esc.employee_id=? AND esc.active=1 ORDER BY sc.kind,sc.name''',[employeeId]);
  Future<void> assignSalaryComponent({
    required String employeeId,required String componentId,required int value}) async {
      BusinessWriteGuard.ensureAllowed('assignSalaryComponent');
      
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final existing=await txn.query(
        'employee_salary_components',
        columns:['id'],
        where:'employee_id=? AND component_id=? AND active=1',
        whereArgs:[employeeId,componentId],
        limit:1,
      );
      if(existing.isEmpty){
        await txn.insert('employee_salary_components',{
          'id':_uuid.v4(),'employee_id':employeeId,'component_id':componentId,'value':value,
          'active':1,'created_at':now,'updated_at':now,
        });
      }else{
        await txn.update('employee_salary_components',{'value':value,'updated_at':now},where:'id=?',whereArgs:[existing.first['id']]);
      }
      await _audit(txn,'employee_salary_component',employeeId,'assign','$componentId/$value');
    });
  }

  Future<List<SalaryAdvanceItem>> advances({String? employeeId}) async {final args=<Object?>[];final where=employeeId==null?'':'WHERE a.employee_id=?';if(employeeId!=null)args.add(employeeId);final rows=await _database.db.rawQuery('''SELECT a.*,e.last_name||' '||e.first_name employee_name FROM salary_advances a JOIN employees e ON e.id=a.employee_id $where ORDER BY a.granted_at DESC''',args);return rows.map((r)=>SalaryAdvanceItem(id:r['id'] as String,employeeId:r['employee_id'] as String,employeeName:r['employee_name'] as String,amount:r['amount'] as int,balance:r['balance'] as int,grantedAt:DateTime.parse(r['granted_at'] as String),status:r['status'] as String,note:r['note'] as String?)).toList();}
  Future<void> grantAdvance({
    required String employeeId,required int amount,required String paymentMethod,required String cashAccountId,String? reference,String? note}) async {
      BusinessWriteGuard.ensureAllowed('grantAdvance');
      if(amount<=0)throw ArgumentError('Montant invalide.');final id=_uuid.v4(),now=DateTime.now().toIso8601String();await _database.db.transaction((txn)async{await ensurePaymentMethodMatchesAccount(txn,paymentMethod,cashAccountId);if(await paymentMethodRequiresReference(txn,paymentMethod)&&(reference??'').trim().isEmpty)throw StateError('Référence obligatoire.');await ensureCashMovementAllowed(txn,cashAccountId);await txn.insert('salary_advances',{'id':id,'employee_id':employeeId,'amount':amount,'balance':amount,'granted_at':now,'payment_method':paymentMethod,'cash_account_id':cashAccountId,'reference':reference?.trim(),'status':'active','note':note?.trim(),'created_at':now});await _audit(txn,'salary_advance',id,'grant','$amount');});}

  Future<List<PayrollPeriodItem>> payrollPeriods() async {final rows=await _database.db.rawQuery('''SELECT p.*,COUNT(e.id) entry_count,COALESCE(SUM(e.gross_salary),0) total_gross,COALESCE(SUM(e.total_deductions),0) total_deductions,COALESCE(SUM(e.net_salary),0) total_net FROM payroll_periods p LEFT JOIN payroll_entries e ON e.period_id=p.id GROUP BY p.id ORDER BY p.start_date DESC''');return rows.map((r)=>PayrollPeriodItem(id:r['id'] as String,label:r['label'] as String,startDate:DateTime.parse(r['start_date'] as String),endDate:DateTime.parse(r['end_date'] as String),status:r['status'] as String,totalGross:(r['total_gross'] as num).toInt(),totalDeductions:(r['total_deductions'] as num).toInt(),totalNet:(r['total_net'] as num).toInt(),entryCount:(r['entry_count'] as num).toInt())).toList();}
  Future<String> createPayrollPeriod({
    required String label,required DateTime startDate,required DateTime endDate}) async {
      BusinessWriteGuard.ensureAllowed('createPayrollPeriod');
      
    if(endDate.isBefore(startDate)) throw ArgumentError('Période invalide.');
    final duplicate=firstIntValue(await _database.db.rawQuery(
      'SELECT COUNT(*) FROM payroll_periods WHERE start_date<=? AND end_date>=?',
      [_dateOnly(endDate),_dateOnly(startDate)],
    ))??0;
    if(duplicate>0) throw StateError('Une période de paie existe déjà sur tout ou partie de ces dates.');
    final id=_uuid.v4(),now=DateTime.now().toIso8601String();
    await _database.db.insert('payroll_periods',{'id':id,'label':label.trim(),'start_date':_dateOnly(startDate),'end_date':_dateOnly(endDate),'status':'draft','created_by':OperatorSession.userId,'created_at':now,'updated_at':now});
    await _generatePayrollEntries(id,startDate,endDate);
    await _audit(_database.db,'payroll_period',id,'create',label);
    return id;
  }
  Future<void> _generatePayrollEntries(String periodId, DateTime startDate, DateTime endDate) async {
    final employees = await _database.db.rawQuery("SELECT id FROM employees WHERE status='active'");
    await _database.db.transaction((txn) async {
      for (final employee in employees) {
        final employeeId = employee['id'] as String;
        final contracts = await txn.rawQuery(
          "SELECT * FROM employment_contracts WHERE employee_id=? AND status='active' AND start_date<=? AND (end_date IS NULL OR end_date>=?) ORDER BY start_date DESC LIMIT 1",
          [employeeId, endDate.toIso8601String(), startDate.toIso8601String()],
        );
        if (contracts.isEmpty) continue;
        final base = contracts.first['base_salary'] as int;
        final entryId = _uuid.v4();
        final stamp = DateTime.now().toIso8601String();
        await txn.insert('payroll_entries', {
          'id': entryId,
          'period_id': periodId,
          'employee_id': employeeId,
          'base_salary': base,
          'gross_salary': base,
          'total_deductions': 0,
          'net_salary': base,
          'status': 'draft',
          'created_at': stamp,
          'updated_at': stamp,
        });

        var earnings = 0;
        var deductions = 0;
        final components = await txn.rawQuery('''
          SELECT esc.value,sc.name,sc.kind,sc.calculation_type
          FROM employee_salary_components esc
          JOIN salary_components sc ON sc.id=esc.component_id
          WHERE esc.employee_id=? AND esc.active=1 AND sc.active=1
        ''', [employeeId]);
        for (final component in components) {
          final raw = component['value'] as int;
          final amount = component['calculation_type'] == 'percentage' ? (base * raw / 100).round() : raw;
          if (component['kind'] == 'deduction') {
            deductions += amount;
          } else {
            earnings += amount;
          }
          await txn.insert('payroll_items', {
            'id': _uuid.v4(),
            'payroll_entry_id': entryId,
            'label': component['name'],
            'kind': component['kind'],
            'amount': amount,
            'source': 'component',
            'created_at': stamp,
          });
        }

        final absentDays = firstIntValue(await txn.rawQuery(
              "SELECT COUNT(*) FROM attendance_records WHERE employee_id=? AND attendance_date>=? AND attendance_date<=? AND status='absent'",
              [employeeId, _dateOnly(startDate), _dateOnly(endDate)],
            )) ?? 0;
        final absenceDeduction = (base / 30 * absentDays).round();
        if (absenceDeduction > 0) {
          deductions += absenceDeduction;
          await txn.insert('payroll_items', {
            'id': _uuid.v4(), 'payroll_entry_id': entryId,
            'label': 'Absences non rémunérées ($absentDays j)', 'kind': 'deduction',
            'amount': absenceDeduction, 'source': 'attendance', 'created_at': stamp,
          });
        }
        final unpaidLeaveDays = firstIntValue(await txn.rawQuery('''
          SELECT COALESCE(SUM(l.days),0) FROM leave_requests l
          JOIN leave_types t ON t.id=l.leave_type_id
          WHERE l.employee_id=? AND l.status='approved' AND t.paid=0
            AND l.start_date<=? AND l.end_date>=?
        ''',[employeeId,_dateOnly(endDate),_dateOnly(startDate)])) ?? 0;
        final unpaidLeaveDeduction=(base/30*unpaidLeaveDays).round();
        if(unpaidLeaveDeduction>0){deductions+=unpaidLeaveDeduction;await txn.insert('payroll_items',{'id':_uuid.v4(),'payroll_entry_id':entryId,'label':'Congés non rémunérés ($unpaidLeaveDays j)','kind':'deduction','amount':unpaidLeaveDeduction,'source':'unpaid_leave','created_at':stamp});}

        final advances = await txn.rawQuery(
          "SELECT id,balance FROM salary_advances WHERE employee_id=? AND status='active' AND balance>0 ORDER BY granted_at",
          [employeeId],
        );
        if (advances.isNotEmpty) {
          final balance = advances.first['balance'] as int;
          final advanceDeduction = balance < base ~/ 4 ? balance : base ~/ 4;
          if (advanceDeduction > 0) {
            deductions += advanceDeduction;
            await txn.insert('payroll_items', {
              'id': _uuid.v4(), 'payroll_entry_id': entryId, 'label': 'Remboursement avance',
              'kind': 'deduction', 'amount': advanceDeduction,
              'source': 'salary_advance:${advances.first['id']}', 'created_at': stamp,
            });
          }
        }

        final gross = base + earnings;
        final net = (gross - deductions).clamp(0, 1 << 31).toInt();
        await txn.update('payroll_entries', {
          'gross_salary': gross,
          'total_deductions': deductions,
          'net_salary': net,
          'updated_at': stamp,
        }, where: 'id=?', whereArgs: [entryId]);
      }
    });
  }

  Future<List<PayrollEntryItem>> payrollEntries(String periodId) async {final rows=await _database.db.rawQuery('''SELECT e.*,emp.last_name||' '||emp.first_name employee_name FROM payroll_entries e JOIN employees emp ON emp.id=e.employee_id WHERE e.period_id=? ORDER BY emp.last_name,emp.first_name''',[periodId]);return rows.map((r)=>PayrollEntryItem(id:r['id'] as String,periodId:r['period_id'] as String,employeeId:r['employee_id'] as String,employeeName:r['employee_name'] as String,baseSalary:r['base_salary'] as int,grossSalary:r['gross_salary'] as int,totalDeductions:r['total_deductions'] as int,netSalary:r['net_salary'] as int,status:r['status'] as String,paymentMethod:r['payment_method'] as String?,cashAccountId:r['cash_account_id'] as String?,paymentReference:r['payment_reference'] as String?,paidAt:r['paid_at']==null?null:DateTime.tryParse(r['paid_at'] as String),expenseId:r['expense_id'] as String?)).toList();}
  Future<List<Map<String,Object?>>> payrollItems(String entryId)=>_database.db.query('payroll_items',where:'payroll_entry_id=?',whereArgs:[entryId],orderBy:'kind,label');
  Future<void> validatePayrollPeriod(String periodId) async {
    BusinessWriteGuard.ensureAllowed('validatePayrollPeriod');final now=DateTime.now().toIso8601String();await _database.db.transaction((txn)async{await txn.update('payroll_entries',{'status':'validated','updated_at':now},where:"period_id=? AND status='draft'",whereArgs:[periodId]);await txn.update('payroll_periods',{'status':'validated','validated_by':OperatorSession.userId,'validated_at':now,'updated_at':now},where:'id=?',whereArgs:[periodId]);await _audit(txn,'payroll_period',periodId,'validate','validated');});}
  Future<void> payPayrollEntry({
    required String entryId,required String paymentMethod,required String cashAccountId,String? reference}) async {
      BusinessWriteGuard.ensureAllowed('payPayrollEntry');
      final now=DateTime.now();await _database.db.transaction((txn)async{final rows=await txn.query('payroll_entries',where:'id=?',whereArgs:[entryId],limit:1);if(rows.isEmpty)throw StateError('Paie introuvable.');final e=rows.first;if(e['status']!='validated')throw StateError('La paie doit être validée avant paiement.');await ensurePaymentMethodMatchesAccount(txn,paymentMethod,cashAccountId);if(await paymentMethodRequiresReference(txn,paymentMethod)&&(reference??'').trim().isEmpty)throw StateError('Référence obligatoire.');await ensureCashMovementAllowed(txn,cashAccountId);var category=await txn.rawQuery("SELECT id FROM expense_categories WHERE lower(name)=lower('Salaires du personnel') LIMIT 1");String categoryId;if(category.isEmpty){categoryId=_uuid.v4();await txn.insert('expense_categories',{'id':categoryId,'name':'Salaires du personnel','active':1});}else{categoryId=category.first['id'] as String;}final employee=(await txn.query('employees',columns:['last_name','first_name'],where:'id=?',whereArgs:[e['employee_id']],limit:1)).first;final period=(await txn.query('payroll_periods',columns:['label'],where:'id=?',whereArgs:[e['period_id']],limit:1)).first['label'];final count=firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM expenses WHERE strftime("%Y",created_at)=?',[now.year.toString()]))??0;final expenseId=_uuid.v4();final number='DEP-${now.year}-${(count+1).toString().padLeft(6,'0')}';await txn.insert('expenses',{'id':expenseId,'category_id':categoryId,'amount':e['net_salary'],'spent_at':now.toIso8601String(),'description':'Paie $period — ${employee['last_name']} ${employee['first_name']}','expense_number':number,'beneficiary':'${employee['last_name']} ${employee['first_name']}','payment_method':paymentMethod,'cash_account_id':cashAccountId,'external_reference':reference?.trim(),'approval_status':'approved','submitted_by':OperatorSession.userId,'submitted_at':now.toIso8601String(),'reviewed_by':OperatorSession.userId,'reviewed_at':now.toIso8601String(),'approval_note':'Créée automatiquement depuis RH/Paie','status':'posted','created_at':now.toIso8601String()});await txn.update('payroll_entries',{'status':'paid','payment_method':paymentMethod,'cash_account_id':cashAccountId,'payment_reference':reference?.trim(),'paid_at':now.toIso8601String(),'expense_id':expenseId,'updated_at':now.toIso8601String()},where:'id=?',whereArgs:[entryId]);final items=await txn.query('payroll_items',where:'payroll_entry_id=? AND source LIKE ?',whereArgs:[entryId,'salary_advance:%']);for(final item in items){final source=item['source'] as String;final advanceId=source.substring('salary_advance:'.length);final amount=item['amount'] as int;final ar=await txn.query('salary_advances',where:'id=?',whereArgs:[advanceId],limit:1);if(ar.isNotEmpty){final old=ar.first['balance'] as int;final next=(old-amount).clamp(0,old).toInt();await txn.update('salary_advances',{'balance':next,'status':next==0?'settled':'active'},where:'id=?',whereArgs:[advanceId]);await txn.insert('salary_advance_repayments',{'id':_uuid.v4(),'advance_id':advanceId,'payroll_entry_id':entryId,'amount':amount,'repaid_at':now.toIso8601String()});}}
      final remaining=firstIntValue(await txn.rawQuery("SELECT COUNT(*) FROM payroll_entries WHERE period_id=? AND status!='paid'",[e['period_id']]))??0;if(remaining==0){await txn.update('payroll_periods',{'status':'paid','updated_at':now.toIso8601String()},where:'id=?',whereArgs:[e['period_id']]);}
      await _audit(txn,'payroll_entry',entryId,'pay','${e['net_salary']}/$paymentMethod');});}

  Future<List<Map<String,Object?>>> hrReportByDepartment() => _database.db.rawQuery('''SELECT COALESCE(d.name,'Sans service') label,COUNT(DISTINCT e.id) employees,COALESCE(SUM(c.base_salary),0) base_payroll FROM employees e LEFT JOIN employee_assignments a ON a.id=(SELECT a2.id FROM employee_assignments a2 WHERE a2.employee_id=e.id ORDER BY a2.start_date DESC LIMIT 1) LEFT JOIN hr_positions p ON p.id=a.position_id LEFT JOIN hr_departments d ON d.id=p.department_id LEFT JOIN employment_contracts c ON c.id=(SELECT c2.id FROM employment_contracts c2 WHERE c2.employee_id=e.id AND c2.status='active' ORDER BY c2.start_date DESC LIMIT 1) WHERE e.status='active' GROUP BY d.id,d.name ORDER BY label''');
  Future<List<Map<String,Object?>>> expiringContracts({int days=60}) {final start=_dateOnly(DateTime.now()),end=_dateOnly(DateTime.now().add(Duration(days:days)));return _database.db.rawQuery('''SELECT c.id,e.employee_number,e.last_name||' '||e.first_name employee_name,c.contract_type,c.end_date,c.base_salary FROM employment_contracts c JOIN employees e ON e.id=c.employee_id WHERE c.status='active' AND c.end_date IS NOT NULL AND c.end_date>=? AND c.end_date<=? ORDER BY c.end_date''',[start,end]);}

  Future<List<Map<String,Object?>>> attendanceReport({required DateTime from,required DateTime to}) => _database.db.rawQuery('''SELECT e.employee_number,e.last_name||' '||e.first_name employee_name, SUM(CASE WHEN a.status='present' THEN 1 ELSE 0 END) present_days,SUM(CASE WHEN a.status='absent' THEN 1 ELSE 0 END) absent_days,SUM(CASE WHEN a.status='late' THEN 1 ELSE 0 END) late_days,SUM(CASE WHEN a.status='leave' THEN 1 ELSE 0 END) leave_days FROM employees e LEFT JOIN attendance_records a ON a.employee_id=e.id AND a.attendance_date>=? AND a.attendance_date<=? GROUP BY e.id ORDER BY e.last_name,e.first_name''',[_dateOnly(from),_dateOnly(to)]);
  Future<List<Map<String,Object?>>> payrollReport() => _database.db.rawQuery('''SELECT p.label,p.start_date,p.end_date,p.status,COUNT(e.id) employees,COALESCE(SUM(e.gross_salary),0) gross,COALESCE(SUM(e.total_deductions),0) deductions,COALESCE(SUM(e.net_salary),0) net FROM payroll_periods p LEFT JOIN payroll_entries e ON e.period_id=p.id GROUP BY p.id ORDER BY p.start_date DESC''');
  Future<List<Map<String,Object?>>> leaveReport() => _database.db.rawQuery('''SELECT e.employee_number,e.last_name||' '||e.first_name employee_name,t.name leave_type,l.start_date,l.end_date,l.days,l.status FROM leave_requests l JOIN employees e ON e.id=l.employee_id JOIN leave_types t ON t.id=l.leave_type_id ORDER BY l.start_date DESC''');

  String _dateOnly(DateTime d)=>DateTime(d.year,d.month,d.day).toIso8601String();
}
