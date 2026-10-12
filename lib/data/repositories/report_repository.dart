import 'package:sqflite_common/utils/utils.dart';

import '../../core/db/app_database.dart';

class FinancialReportSummary {
  const FinancialReportSummary({required this.expected,required this.allocated,required this.revenue,required this.expenses});
  final int expected,allocated,revenue,expenses;
  int get outstanding=>expected-allocated; int get cashBalance=>revenue-expenses; double get recoveryRate=>expected<=0?0:allocated/expected;
}

class ReportFilter {
  const ReportFilter({this.cycleId,this.classroomId,this.familyId,this.schoolYearId,this.periodKey,this.start,this.end});
  final String? cycleId,classroomId,familyId,schoolYearId,periodKey; final DateTime? start,end;
  bool get hasSchoolScope=>cycleId!=null||classroomId!=null||familyId!=null;
}

class LedgerEntry {
  const LedgerEntry({required this.date,required this.reference,required this.description,required this.debit,required this.credit,required this.balance});
  final DateTime date; final String reference,description; final int debit,credit,balance;
}

class ReportRepository {
  ReportRepository(this._db); final AppDatabase _db;

  Future<String?> _effectiveSchoolYearId(ReportFilter filter) async {
    if (filter.schoolYearId != null) return filter.schoolYearId;
    final rows = await _db.db.query(
      'school_years',
      columns: ['id'],
      where: 'is_active = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  Future<({DateTime start, DateTime end})?> _schoolYearBounds(String? yearId) async {
    if (yearId == null) return null;
    final rows = await _db.db.query(
      'school_years',
      columns: ['start_date','end_date'],
      where: 'id = ?',
      whereArgs: [yearId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      start: DateTime.parse(rows.first['start_date'] as String),
      end: DateTime.parse(rows.first['end_date'] as String).add(const Duration(microseconds: 1)),
    );
  }

  ({String sql,List<Object?> args}) _studentScope(ReportFilter f,{String studentAlias='s'}){
    final c=<String>[];final a=<Object?>[];
    if(f.cycleId!=null){c.add('cy.id = ?');a.add(f.cycleId);}
    if(f.classroomId!=null){c.add('c.id = ?');a.add(f.classroomId);}
    if(f.familyId!=null){c.add('$studentAlias.family_id = ?');a.add(f.familyId);}
    return (sql:c.isEmpty?'':c.join(' AND '),args:a);
  }

  Future<List<Map<String,Object?>>> unpaid({ReportFilter filter=const ReportFilter()}) async {
    final scope=_studentScope(filter);final c=<String>["d.status != 'paid'"];final a=<Object?>[];
    final yearId=await _effectiveSchoolYearId(filter);
    if (yearId == null) throw StateError('Aucune année scolaire active pour les impayés.');
    c.add('d.school_year_id = ?'); a.add(yearId);
    if(scope.sql.isNotEmpty){c.add(scope.sql);a.addAll(scope.args);} if(filter.start!=null){c.add('COALESCE(d.due_date,d.created_at) >= ?');a.add(filter.start!.toIso8601String());} if(filter.end!=null){c.add('COALESCE(d.due_date,d.created_at) < ?');a.add(filter.end!.toIso8601String());}
    return _db.db.rawQuery('''SELECT d.id due_id,s.registration_number,s.last_name||' '||s.first_name student,cy.name cycle,c.name classroom,fam.name family,f.name fee,d.period_key,d.amount_due,d.amount_paid,(d.amount_due-d.amount_paid) balance,d.due_date
      FROM dues d JOIN students s ON s.id=d.student_id JOIN student_enrollments se ON se.student_id=s.id AND se.school_year_id=d.school_year_id JOIN classrooms c ON c.id=se.classroom_id JOIN cycles cy ON cy.id=c.cycle_id LEFT JOIN families fam ON fam.id=s.family_id JOIN fee_categories f ON f.id=d.fee_id
      WHERE ${c.join(' AND ')} ORDER BY d.due_date,s.last_name''',a);
  }

  Future<List<Map<String,Object?>>> billingDues({ReportFilter filter=const ReportFilter()}) async {
    final scope=_studentScope(filter);final c=<String>['1=1'];final a=<Object?>[];
    final yearId=await _effectiveSchoolYearId(filter); if(yearId!=null){c.add('d.school_year_id = ?');a.add(yearId);}
    if(scope.sql.isNotEmpty){c.add(scope.sql);a.addAll(scope.args);} if(filter.periodKey!=null){c.add('d.period_key = ?');a.add(filter.periodKey);} if(filter.start!=null){c.add('COALESCE(d.due_date,d.created_at) >= ?');a.add(filter.start!.toIso8601String());} if(filter.end!=null){c.add('COALESCE(d.due_date,d.created_at) < ?');a.add(filter.end!.toIso8601String());}
    return _db.db.rawQuery('''SELECT d.id due_id,s.id student_id,s.registration_number,s.last_name||' '||s.first_name student,cy.name cycle,c.name classroom,fam.name family,COALESCE((SELECT sg.name FROM student_guardians sg WHERE sg.student_id=s.id AND sg.is_primary=1 ORDER BY sg.created_at LIMIT 1),s.guardian_name) guardian_name,COALESCE((SELECT sg.phone FROM student_guardians sg WHERE sg.student_id=s.id AND sg.is_primary=1 ORDER BY sg.created_at LIMIT 1),s.guardian_phone) guardian_phone,f.name fee,d.period_key,d.amount_due,d.amount_paid,(d.amount_due-d.amount_paid) balance,d.due_date,d.status
      FROM dues d JOIN students s ON s.id=d.student_id JOIN student_enrollments se ON se.student_id=s.id AND se.school_year_id=d.school_year_id JOIN classrooms c ON c.id=se.classroom_id JOIN cycles cy ON cy.id=c.cycle_id LEFT JOIN families fam ON fam.id=s.family_id JOIN fee_categories f ON f.id=d.fee_id
      WHERE ${c.join(' AND ')} ORDER BY d.due_date DESC,s.last_name''',a);
  }

  Future<Map<String,Object?>> billingDetail(String dueId) async {
    final rows=await _db.db.rawQuery('''SELECT d.id due_id,s.registration_number,s.last_name||' '||s.first_name student,cy.name cycle,c.name classroom,fam.name family,COALESCE((SELECT sg.name FROM student_guardians sg WHERE sg.student_id=s.id AND sg.is_primary=1 ORDER BY sg.created_at LIMIT 1),s.guardian_name) guardian_name,COALESCE((SELECT sg.phone FROM student_guardians sg WHERE sg.student_id=s.id AND sg.is_primary=1 ORDER BY sg.created_at LIMIT 1),s.guardian_phone) guardian_phone,f.name fee,d.period_key,d.amount_due,d.amount_paid,(d.amount_due-d.amount_paid) balance,d.due_date,d.status,
      e.name establishment,e.phone establishment_phone,e.email establishment_email,e.address establishment_address,e.approval_number,COALESCE(sy.label,e.school_year_label) school_year_label
      FROM dues d JOIN students s ON s.id=d.student_id JOIN student_enrollments se ON se.student_id=s.id AND se.school_year_id=d.school_year_id JOIN classrooms c ON c.id=se.classroom_id JOIN cycles cy ON cy.id=c.cycle_id LEFT JOIN families fam ON fam.id=s.family_id JOIN fee_categories f ON f.id=d.fee_id LEFT JOIN establishments e ON e.id=(SELECT id FROM establishments ORDER BY created_at LIMIT 1) LEFT JOIN school_years sy ON sy.id=d.school_year_id WHERE d.id=? LIMIT 1''',[dueId]);
    if(rows.isEmpty)throw StateError('Échéance introuvable.');return rows.first;
  }

  Future<List<Map<String,Object?>>> cashJournal({ReportFilter filter=const ReportFilter()}) async {
    final paymentConditions=<String>["p.status='posted'"];final args=<Object?>[];
    final yearId=await _effectiveSchoolYearId(filter); final yearBounds=await _schoolYearBounds(yearId); if(yearId!=null){paymentConditions.add('p.school_year_id = ?');args.add(yearId);}
    if(filter.start!=null){paymentConditions.add('p.paid_at >= ?');args.add(filter.start!.toIso8601String());} if(filter.end!=null){paymentConditions.add('p.paid_at < ?');args.add(filter.end!.toIso8601String());}
    if(filter.familyId!=null){paymentConditions.add('(p.family_id = ? OR s.family_id = ?)');args.addAll([filter.familyId,filter.familyId]);}
    if(filter.classroomId!=null){paymentConditions.add('EXISTS (SELECT 1 FROM payment_allocations pa JOIN dues d ON d.id=pa.due_id JOIN student_enrollments sex ON sex.student_id=d.student_id AND sex.school_year_id=d.school_year_id WHERE pa.payment_id=p.id AND sex.classroom_id=?)');args.add(filter.classroomId);}
    if(filter.cycleId!=null){paymentConditions.add('EXISTS (SELECT 1 FROM payment_allocations pa JOIN dues d ON d.id=pa.due_id JOIN student_enrollments sex ON sex.student_id=d.student_id AND sex.school_year_id=d.school_year_id JOIN classrooms cx ON cx.id=sex.classroom_id WHERE pa.payment_id=p.id AND cx.cycle_id=?)');args.add(filter.cycleId);}
    final payments=await _db.db.rawQuery('''SELECT p.paid_at date,'Recette' type,p.receipt_number reference,p.amount amount,COALESCE(s.last_name||' '||s.first_name,fam.name,p.note,'Paiement') description FROM payments p LEFT JOIN students s ON s.id=p.student_id LEFT JOIN families fam ON fam.id=COALESCE(p.family_id,s.family_id) WHERE ${paymentConditions.join(' AND ')}''',args);
    final refundConditions=<String>["p.status='posted'"]; final refundArgs=<Object?>[];
    if(yearId!=null){refundConditions.add('p.school_year_id = ?');refundArgs.add(yearId);}
    if(filter.start!=null){refundConditions.add('r.refunded_at >= ?');refundArgs.add(filter.start!.toIso8601String());}
    if(filter.end!=null){refundConditions.add('r.refunded_at < ?');refundArgs.add(filter.end!.toIso8601String());}
    if(filter.familyId!=null){refundConditions.add('(p.family_id = ? OR s.family_id = ?)');refundArgs.addAll([filter.familyId,filter.familyId]);}
    if(filter.classroomId!=null){refundConditions.add('EXISTS (SELECT 1 FROM payment_allocations pa JOIN dues d ON d.id=pa.due_id JOIN student_enrollments sex ON sex.student_id=d.student_id AND sex.school_year_id=d.school_year_id WHERE pa.payment_id=p.id AND sex.classroom_id=?)');refundArgs.add(filter.classroomId);}
    if(filter.cycleId!=null){refundConditions.add('EXISTS (SELECT 1 FROM payment_allocations pa JOIN dues d ON d.id=pa.due_id JOIN student_enrollments sex ON sex.student_id=d.student_id AND sex.school_year_id=d.school_year_id JOIN classrooms cx ON cx.id=sex.classroom_id WHERE pa.payment_id=p.id AND cx.cycle_id=?)');refundArgs.add(filter.cycleId);}
    final refunds=await _db.db.rawQuery('''SELECT r.refunded_at date,'Remboursement' type,p.receipt_number||'-R' reference,-r.amount amount,COALESCE(s.last_name||' '||s.first_name,fam.name,r.reason,'Remboursement') description FROM payment_refunds r JOIN payments p ON p.id=r.payment_id LEFT JOIN students s ON s.id=p.student_id LEFT JOIN families fam ON fam.id=COALESCE(p.family_id,s.family_id) WHERE ${refundConditions.join(' AND ')}''',refundArgs);
    if(filter.hasSchoolScope){final scoped=<Map<String,Object?>>[...payments,...refunds];scoped.sort((a,b)=>('${b['date']}').compareTo('${a['date']}'));return scoped;}
    final expC=<String>["status='posted'","approval_status='approved'"];final expA=<Object?>[];
    final expenseStart=filter.start??yearBounds?.start; final expenseEnd=filter.end??yearBounds?.end;
    if(expenseStart!=null){expC.add('spent_at >= ?');expA.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){expC.add('spent_at < ?');expA.add(expenseEnd.toIso8601String());}
    final expenses=await _db.db.rawQuery("SELECT spent_at date,'Dépense' type,id reference,-amount amount,COALESCE(description,'Dépense') description FROM expenses WHERE ${expC.join(' AND ')}",expA);
    final advanceConditions=<String>["status!='annule'"];final advanceArgs=<Object?>[];
    if(expenseStart!=null){advanceConditions.add('granted_at >= ?');advanceArgs.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){advanceConditions.add('granted_at < ?');advanceArgs.add(expenseEnd.toIso8601String());}
    final salaryAdvances=await _db.db.rawQuery("SELECT a.granted_at date,'Avance salaire' type,a.id reference,-a.amount amount,e.last_name||' '||e.first_name||' · avance sur salaire' description FROM salary_advances a JOIN employees e ON e.id=a.employee_id WHERE ${advanceConditions.join(' AND ')}",advanceArgs);
    final transferConditions=<String>["status='posted'"]; final transferArgs=<Object?>[];
    if(expenseStart!=null){transferConditions.add('transferred_at >= ?');transferArgs.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){transferConditions.add('transferred_at < ?');transferArgs.add(expenseEnd.toIso8601String());}
    final transferRows=await _db.db.rawQuery('''SELECT t.transferred_at date,'Transfert' type,t.id reference,t.amount,
      fa.name from_name,ta.name to_name,COALESCE(t.note,t.reference,'Transfert interne') description
      FROM cash_transfers t JOIN cash_accounts fa ON fa.id=t.from_account_id JOIN cash_accounts ta ON ta.id=t.to_account_id
      WHERE ${transferConditions.join(' AND ')}''',transferArgs);
    final transfers=<Map<String,Object?>>[];
    for(final row in transferRows){
      transfers.add({...row,'amount':0,'description':'${row['from_name']} → ${row['to_name']} · ${row['description']} · ${row['amount']} FCFA'});
    }
    final supplierConditions=<String>['1=1']; final supplierArgs=<Object?>[];
    if(expenseStart!=null){supplierConditions.add('sp.paid_at >= ?');supplierArgs.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){supplierConditions.add('sp.paid_at < ?');supplierArgs.add(expenseEnd.toIso8601String());}
    final supplierPayments=await _db.db.rawQuery('''SELECT sp.paid_at date,'Règlement fournisseur' type,COALESCE(sp.reference,si.invoice_number,sp.id) reference,-sp.amount amount,'Fournisseur · '||si.supplier_name||' · '||si.description description FROM supplier_payments sp JOIN supplier_invoices si ON si.id=sp.supplier_invoice_id WHERE ${supplierConditions.join(' AND ')}''',supplierArgs);
    final saleConditions=<String>["ad.disposal_type='sale'","ad.sale_amount>0","ad.cash_account_id IS NOT NULL"]; final saleArgs=<Object?>[];
    if(expenseStart!=null){saleConditions.add('ad.disposal_date >= ?');saleArgs.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){saleConditions.add('ad.disposal_date < ?');saleArgs.add(expenseEnd.toIso8601String());}
    final assetSales=await _db.db.rawQuery('''SELECT ad.disposal_date date,'Cession patrimoine' type,COALESCE(ad.reference,ad.id) reference,ad.sale_amount amount,'Vente · '||a.asset_number||' · '||a.name description FROM asset_disposals ad JOIN assets a ON a.id=ad.asset_id WHERE ${saleConditions.join(' AND ')}''',saleArgs);
    final all=<Map<String,Object?>>[...payments,...refunds,...expenses,...salaryAdvances,...supplierPayments,...assetSales,...transfers];all.sort((a,b)=>('${b['date']}').compareTo('${a['date']}'));return all;
  }


  Future<List<Map<String,Object?>>> agingReport({ReportFilter filter=const ReportFilter()}) async {
    final now=DateTime.now();
    final today=DateTime(now.year,now.month,now.day);
    final rows=await unpaid(filter:filter);
    final buckets=<String,int>{'0-30 jours':0,'31-60 jours':0,'61-90 jours':0,'90+ jours':0};
    for(final row in rows){
      final raw=row['due_date']; if(raw==null) continue;
      final date=DateTime.parse(raw as String);
      final dueDay=DateTime(date.year,date.month,date.day);
      if (!dueDay.isBefore(today)) continue;
      final days=today.difference(dueDay).inDays;
      final key=days<=30?'0-30 jours':days<=60?'31-60 jours':days<=90?'61-90 jours':'90+ jours';
      buckets[key]=buckets[key]!+(row['balance'] as int);
    }
    return buckets.entries.map((e)=>{'anciennete':e.key,'solde':e.value}).toList();
  }

  Future<List<Map<String, Object?>>> recoveryPerformance({
    ReportFilter filter = const ReportFilter(),
    String groupBy = 'classroom',
  }) async {
    const allowed = {'cycle', 'classroom', 'fee'};
    if (!allowed.contains(groupBy)) throw ArgumentError('Regroupement de recouvrement invalide.');
    final yearId = await _effectiveSchoolYearId(filter);
    final conditions = <String>['1=1'];
    final args = <Object?>[];
    if (yearId != null) {
      conditions.add('d.school_year_id=?');
      args.add(yearId);
    }
    if (filter.cycleId != null) {
      conditions.add('cy.id=?');
      args.add(filter.cycleId);
    }
    if (filter.classroomId != null) {
      conditions.add('c.id=?');
      args.add(filter.classroomId);
    }
    if (filter.familyId != null) {
      conditions.add('s.family_id=?');
      args.add(filter.familyId);
    }
    if (filter.start != null) {
      conditions.add('COALESCE(d.due_date,d.created_at)>=?');
      args.add(filter.start!.toIso8601String());
    }
    if (filter.end != null) {
      conditions.add('COALESCE(d.due_date,d.created_at)<?');
      args.add(filter.end!.toIso8601String());
    }

    final groupId = switch (groupBy) {
      'cycle' => 'cy.id',
      'fee' => 'fc.id',
      _ => 'c.id',
    };
    final groupLabel = switch (groupBy) {
      'cycle' => 'cy.name',
      'fee' => 'fc.name',
      _ => "cy.name || ' · ' || c.name",
    };
    return _db.db.rawQuery('''
      SELECT $groupId group_id,$groupLabel label,
             COUNT(DISTINCT d.id) dues_count,
             COUNT(DISTINCT d.student_id) students_count,
             COALESCE(SUM(d.amount_due),0) expected,
             COALESCE(SUM(d.amount_paid),0) collected,
             COALESCE(SUM(d.amount_due-d.amount_paid),0) outstanding,
             CASE WHEN SUM(d.amount_due)=0 THEN 0.0
                  ELSE (1.0*SUM(d.amount_paid)/SUM(d.amount_due))*100 END rate
      FROM dues d
      JOIN students s ON s.id=d.student_id
      JOIN student_enrollments se ON se.student_id=s.id AND se.school_year_id=d.school_year_id
      JOIN classrooms c ON c.id=se.classroom_id
      JOIN cycles cy ON cy.id=c.cycle_id
      JOIN fee_categories fc ON fc.id=d.fee_id
      WHERE ${conditions.join(' AND ')}
      GROUP BY $groupId,$groupLabel
      ORDER BY rate ASC,outstanding DESC,label
    ''', args);
  }

  Future<List<Map<String,Object?>>> expenseReport({ReportFilter filter=const ReportFilter()}) async {
    final yearId=await _effectiveSchoolYearId(filter);
    final bounds=await _schoolYearBounds(yearId);
    final c=<String>["e.status='posted'","e.approval_status='approved'"];final a=<Object?>[];
    final effectiveStart=filter.start??bounds?.start; final effectiveEnd=filter.end??bounds?.end;
    if(effectiveStart!=null){c.add('e.spent_at >= ?');a.add(effectiveStart.toIso8601String());}
    if(effectiveEnd!=null){c.add('e.spent_at < ?');a.add(effectiveEnd.toIso8601String());}
    final direct=await _db.db.rawQuery('''SELECT ec.name category,COUNT(*) operations,COALESCE(SUM(e.amount),0) total FROM expenses e JOIN expense_categories ec ON ec.id=e.category_id WHERE ${c.join(' AND ')} GROUP BY ec.id''',a);
    final supplierC=<String>['1=1']; final supplierA=<Object?>[];
    if(effectiveStart!=null){supplierC.add('sp.paid_at >= ?');supplierA.add(effectiveStart.toIso8601String());}
    if(effectiveEnd!=null){supplierC.add('sp.paid_at < ?');supplierA.add(effectiveEnd.toIso8601String());}
    final suppliers=await _db.db.rawQuery('''SELECT 'Fournisseurs · '||aa.name category,COUNT(*) operations,COALESCE(SUM(sp.amount),0) total FROM supplier_payments sp JOIN supplier_invoices si ON si.id=sp.supplier_invoice_id JOIN accounting_accounts aa ON aa.code=si.expense_account_code WHERE ${supplierC.join(' AND ')} GROUP BY aa.code''',supplierA);
    final merged=<String,Map<String,Object?>>{};
    for(final row in [...direct,...suppliers]){final key='${row['category']}';final previous=merged[key];merged[key]={'category':key,'operations':((previous?['operations'] as num?)?.toInt()??0)+((row['operations'] as num?)?.toInt()??0),'total':((previous?['total'] as num?)?.toInt()??0)+((row['total'] as num?)?.toInt()??0)};}
    final result=merged.values.toList();result.sort((x,y)=>((y['total'] as num).toInt()).compareTo((x['total'] as num).toInt()));return result;
  }

  Future<List<LedgerEntry>> grandLedger({ReportFilter filter=const ReportFilter()}) async {
    final rows=await cashJournal(filter:filter);rows.sort((a,b)=>('${a['date']}').compareTo('${b['date']}'));var balance=0;final result=<LedgerEntry>[];
    for(final r in rows){final amount=r['amount'] as int;final credit=amount>0?amount:0;final debit=amount<0?-amount:0;balance+=credit-debit;result.add(LedgerEntry(date:DateTime.parse(r['date'] as String),reference:'${r['reference']}',description:'${r['type']} · ${r['description']}',debit:debit,credit:credit,balance:balance));}return result.reversed.toList();
  }


  Future<List<Map<String,Object?>>> enrollmentStatusReport({ReportFilter filter=const ReportFilter()}) async {
    final yearId=await _effectiveSchoolYearId(filter);
    final where=<String>['1=1'];final args=<Object?>[];
    if(yearId!=null){where.add('se.school_year_id=?');args.add(yearId);}
    if(filter.cycleId!=null){where.add('cy.id=?');args.add(filter.cycleId);}
    if(filter.classroomId!=null){where.add('c.id=?');args.add(filter.classroomId);}
    return _db.db.rawQuery('''SELECT cy.name cycle,c.name classroom,se.status,COUNT(*) total
      FROM student_enrollments se JOIN classrooms c ON c.id=se.classroom_id JOIN cycles cy ON cy.id=c.cycle_id
      WHERE ${where.join(' AND ')} GROUP BY cy.id,c.id,se.status ORDER BY cy.sort_order,c.name,se.status''',args);
  }

  Future<List<Map<String,Object?>>> incompleteStudentFiles({ReportFilter filter=const ReportFilter()}) async {
    final yearId=await _effectiveSchoolYearId(filter);
    final where=<String>["dr.active=1 AND dr.required=1"];final args=<Object?>[];
    if(yearId!=null){where.add('se.school_year_id=?');args.add(yearId);}
    if(filter.cycleId!=null){where.add('cy.id=?');args.add(filter.cycleId);}
    if(filter.classroomId!=null){where.add('c.id=?');args.add(filter.classroomId);}
    return _db.db.rawQuery('''SELECT s.registration_number,s.last_name||' '||s.first_name student,cy.name cycle,c.name classroom,
      COUNT(dr.id) required_count,
      SUM(CASE WHEN EXISTS(SELECT 1 FROM student_documents sd WHERE sd.student_id=s.id AND lower(trim(sd.document_type))=lower(trim(dr.name))) THEN 1 ELSE 0 END) present_count,
      GROUP_CONCAT(CASE WHEN NOT EXISTS(SELECT 1 FROM student_documents sd WHERE sd.student_id=s.id AND lower(trim(sd.document_type))=lower(trim(dr.name))) THEN dr.name END, ', ') missing
      FROM students s JOIN student_enrollments se ON se.student_id=s.id JOIN classrooms c ON c.id=se.classroom_id JOIN cycles cy ON cy.id=c.cycle_id
      CROSS JOIN document_requirements dr WHERE ${where.join(' AND ')}
      GROUP BY s.id HAVING present_count < required_count ORDER BY cy.sort_order,c.name,s.last_name,s.first_name''',args);
  }
  Future<FinancialReportSummary> financialSummary({DateTime? start,DateTime? end,String? schoolYearId}) async {
    final filter=ReportFilter(schoolYearId:schoolYearId,start:start,end:end);
    final yearId=await _effectiveSchoolYearId(filter);
    String between(String column)=>start==null||end==null?'':' AND $column >= ? AND $column < ?';
    List<Object?> periodArgs()=>start==null||end==null?<Object?>[]:[start.toIso8601String(),end.toIso8601String()];
    Future<int> scalar(String sql,[List<Object?>? values])async=>firstIntValue(await _db.db.rawQuery(sql,values))??0;

    final dueWhere=yearId==null?'1=1':'school_year_id = ?';
    final dueArgs=<Object?>[if(yearId!=null) yearId,...periodArgs()];
    final expected=await scalar("SELECT COALESCE(SUM(amount_due),0) FROM dues WHERE $dueWhere${between('COALESCE(due_date,created_at)')}",dueArgs);
    final allocated=await scalar("SELECT COALESCE(SUM(amount_paid),0) FROM dues WHERE $dueWhere${between('COALESCE(due_date,created_at)')}",dueArgs);

    final paymentWhere=yearId==null?"status='posted'":"status='posted' AND school_year_id = ?";
    final paymentArgs=<Object?>[if(yearId!=null) yearId,...periodArgs()];
    final grossRevenue=await scalar("SELECT COALESCE(SUM(amount),0) FROM payments WHERE $paymentWhere${between('paid_at')}",paymentArgs);
    final refundWhere=yearId==null?'1=1':'p.school_year_id = ?';
    final refundArgs=<Object?>[if(yearId!=null) yearId,...periodArgs()];
    final refunds=await scalar("SELECT COALESCE(SUM(r.amount),0) FROM payment_refunds r JOIN payments p ON p.id=r.payment_id WHERE $refundWhere${between('r.refunded_at')}",refundArgs);
    final bounds=await _schoolYearBounds(yearId);
    final cashStart=start??bounds?.start; final cashEnd=end??bounds?.end;
    final saleConditions=<String>["disposal_type='sale'","sale_amount>0","cash_account_id IS NOT NULL"]; final saleArgs=<Object?>[];
    if(cashStart!=null){saleConditions.add('disposal_date >= ?');saleArgs.add(cashStart.toIso8601String());}
    if(cashEnd!=null){saleConditions.add('disposal_date < ?');saleArgs.add(cashEnd.toIso8601String());}
    final assetSaleRevenue=await scalar("SELECT COALESCE(SUM(sale_amount),0) FROM asset_disposals WHERE ${saleConditions.join(' AND ')}",saleArgs);
    final revenue=grossRevenue-refunds+assetSaleRevenue;
    final expenseStart=cashStart; final expenseEnd=cashEnd;
    final expenseConditions=<String>["status='posted'","approval_status='approved'"]; final expenseArgs=<Object?>[];
    if(expenseStart!=null){expenseConditions.add('spent_at >= ?');expenseArgs.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){expenseConditions.add('spent_at < ?');expenseArgs.add(expenseEnd.toIso8601String());}
    final directExpenses=await scalar("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE ${expenseConditions.join(' AND ')}",expenseArgs);
    final supplierConditions=<String>['1=1']; final supplierArgs=<Object?>[];
    if(expenseStart!=null){supplierConditions.add('paid_at >= ?');supplierArgs.add(expenseStart.toIso8601String());}
    if(expenseEnd!=null){supplierConditions.add('paid_at < ?');supplierArgs.add(expenseEnd.toIso8601String());}
    final supplierExpenses=await scalar("SELECT COALESCE(SUM(amount),0) FROM supplier_payments WHERE ${supplierConditions.join(' AND ')}",supplierArgs);
    return FinancialReportSummary(expected:expected,allocated:allocated,revenue:revenue,expenses:directExpenses+supplierExpenses);
  }

  static const _monthNames=['Janv.','Févr.','Mars','Avr.','Mai','Juin','Juil.','Août','Sept.','Oct.','Nov.','Déc.'];

  /// Retourne les recettes/dépenses/bénéfice mois par mois. Lorsqu'une plage
  /// est fournie, les premier et dernier mois sont limités aux dates choisies.
  Future<List<Map<String,Object?>>> monthlyFinancialTrend({int months=6,DateTime? start,DateTime? end,String? schoolYearId}) async {
    final result=<Map<String,Object?>>[];
    final now=DateTime.now();
    final rangeStart=start??DateTime(now.year,now.month-months+1,1);
    final rangeEnd=end??DateTime(now.year,now.month+1,1);
    var monthDate=DateTime(rangeStart.year,rangeStart.month,1);
    while(monthDate.isBefore(rangeEnd)){
      final nextMonth=DateTime(monthDate.year,monthDate.month+1,1);
      final sliceStart=rangeStart.isAfter(monthDate)?rangeStart:monthDate;
      final sliceEnd=rangeEnd.isBefore(nextMonth)?rangeEnd:nextMonth;
      final summary=await financialSummary(start:sliceStart,end:sliceEnd,schoolYearId:schoolYearId);
      result.add({
        'label':'${_monthNames[monthDate.month-1]} ${monthDate.year}',
        'revenue':summary.revenue,
        'expenses':summary.expenses,
        'balance':summary.cashBalance,
      });
      monthDate=nextMonth;
    }
    return result;
  }
}
