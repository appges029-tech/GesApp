import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/db/app_database.dart';

class AlertsRepository {
  AlertsRepository(this._db);
  final AppDatabase _db;
  static const _uuid=Uuid();


  Future<int> _intSetting(String key, int fallback) async {
    final rows=await _db.db.query('app_settings',columns:['value'],where:'key=?',whereArgs:[key],limit:1);
    return rows.isEmpty ? fallback : int.tryParse('${rows.first['value']}') ?? fallback;
  }

  Future<int> refreshOperationalAlerts() async {
    var created=0;
    created+=await _refreshOverdue();
    created+=await _refreshCapacity();
    created+=await _refreshRecoveryFollowUps();
    created+=await _refreshUpcomingDues();
    created+=await _refreshBackupHealth();
    created+=await _refreshIntegrityHealth();
    created+=await _refreshRecurringExpenses();
    created+=await _refreshHrContracts();
    created+=await _refreshHrDocuments();
    created+=await _refreshHrPayroll();
    created+=await _refreshAssetWarranties();
    created+=await _refreshAssetMaintenance();
    created+=await _refreshAssetInventory();
    return created;
  }

  Future<int> refreshOverdueAlerts()=>_refreshOverdue();

  Future<int> _refreshOverdue() async {
    final now = DateTime.now();
    final highDays=await _intSetting('alert.overdue.high_days',30);
    final criticalDays=await _intSetting('alert.overdue.critical_days',90);
    final nowIso = now.toIso8601String();
    final activeYear = await _db.db.query(
      'school_years',
      columns: ['id'],
      where: 'is_active = 1',
      limit: 1,
    );
    final yearId = activeYear.isEmpty ? null : activeYear.first['id'] as String?;
    final yearClause = yearId == null ? '' : ' AND school_year_id = ?';
    final yearArgs = yearId == null ? <Object?>[nowIso] : <Object?>[nowIso, yearId];

    await _db.db.rawUpdate(
      "UPDATE alerts SET is_read=1,status='resolved' "
      "WHERE type='overdue' AND target_id NOT IN "
      "(SELECT id FROM dues WHERE status!='paid' AND due_date IS NOT NULL AND due_date<?$yearClause)",
      yearArgs,
    );
    final rows = await _db.db.rawQuery('''
      SELECT d.id,s.last_name||' '||s.first_name beneficiary,c.name classroom,
             (d.amount_due-d.amount_paid) balance,d.due_date
      FROM dues d
      JOIN students s ON s.id=d.student_id
      JOIN student_enrollments se
        ON se.student_id=d.student_id AND se.school_year_id=d.school_year_id
      JOIN classrooms c ON c.id=se.classroom_id
      WHERE d.status!='paid' AND d.due_date IS NOT NULL AND d.due_date<?
        ${yearId == null ? '' : 'AND d.school_year_id = ?'}
    ''', yearArgs);
    var created = 0;
    for (final row in rows) {
      final dueDate = DateTime.parse(row['due_date'] as String);
      final days = now.difference(dueDate).inDays;
      final severity = days >= criticalDays ? 'critical' : days >= highDays ? 'high' : 'warning';
      final existingRows = await _db.db.query(
        'alerts',
        columns: ['id','severity'],
        where: "type='overdue' AND target_id=? AND status!='archived'",
        whereArgs: [row['id']],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final previousSeverity = existingRows.first['severity'] as String?;
        final escalated =
            (previousSeverity == 'warning' && (severity == 'high' || severity == 'critical')) ||
            (previousSeverity == 'high' && severity == 'critical');
        await _db.db.update(
          'alerts',
          {
            'message':'${row['beneficiary']} · ${row['classroom']} — ${row['balance']} XAF · $days j de retard',
            'severity':severity,
            if (escalated) 'notification_sent':0,
          },
          where:'id=?',
          whereArgs:[existingRows.first['id']],
        );
        continue;
      }
      await _db.db.insert('alerts',{
        'id':_uuid.v4(),'type':'overdue','target_type':'due','target_id':row['id'],
        'title':'Impayé en retard',
        'message':'${row['beneficiary']} · ${row['classroom']} — ${row['balance']} XAF · $days j de retard',
        'due_at':row['due_date'],'is_read':0,'severity':severity,'status':'new','created_at':nowIso,
      });
      created++;
    }
    return created;
  }

  Future<int> _refreshCapacity() async {
    final now=DateTime.now().toIso8601String();
    final capacityPercent=await _intSetting('alert.capacity_percent',90);
    final activeYear=await _db.db.query('school_years',columns:['id'],where:'is_active=1',limit:1);
    final yearId=activeYear.isEmpty?null:activeYear.first['id'] as String?;
    final rows=yearId==null
      ? await _db.db.rawQuery('''SELECT c.id,c.name,c.capacity,COUNT(s.id) occupied FROM classrooms c LEFT JOIN students s ON s.classroom_id=c.id AND s.status='active' WHERE c.active=1 AND c.capacity IS NOT NULL GROUP BY c.id HAVING COUNT(s.id)*100>=c.capacity*$capacityPercent''')
      : await _db.db.rawQuery('''SELECT c.id,c.name,c.capacity,COUNT(se.student_id) occupied
          FROM classrooms c
          LEFT JOIN student_enrollments se ON se.classroom_id=c.id AND se.school_year_id=? AND se.status='active'
          WHERE c.active=1 AND c.capacity IS NOT NULL
          GROUP BY c.id HAVING COUNT(se.student_id)*100>=c.capacity*$capacityPercent''',[yearId]);
    var created=0;
    for(final row in rows){
      final cap=row['capacity'] as int;final occ=row['occupied'] as int;final full=occ>=cap;
      final existingRows=await _db.db.query('alerts',columns:['id','severity','title'],where:"type='capacity' AND target_id=? AND status!='archived'",whereArgs:[row['id']],limit:1);
      if(existingRows.isNotEmpty){
        final becameFull=full && existingRows.first['title']!='Classe complète';
        await _db.db.update('alerts',{'title':full?'Classe complète':'Classe presque pleine','message':'${row['name']} — $occ/$cap élèves','severity':full?'high':'warning',if(becameFull)'notification_sent':0},where:'id=?',whereArgs:[existingRows.first['id']]);
        continue;
      }
      await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'capacity','target_type':'classroom','target_id':row['id'],'title':full?'Classe complète':'Classe presque pleine','message':'${row['name']} — $occ/$cap élèves','due_at':null,'is_read':0,'severity':full?'high':'warning','status':'new','created_at':now});created++;
    }
    final activeIds=rows.map((r)=>'${r['id']}').toList();
    if(activeIds.isEmpty){await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='capacity' AND status!='archived'");}
    else{await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='capacity' AND status!='archived' AND target_id NOT IN (${List.filled(activeIds.length,'?').join(',')})",whereArgs:activeIds);}
    return created;
  }

  Future<int> _refreshRecoveryFollowUps() async {
    final now = DateTime.now().toIso8601String();
    await _db.db.rawUpdate('''
      UPDATE alerts SET is_read=1,status='resolved'
      WHERE type='recovery_followup' AND target_id NOT IN (
        SELECT ra.id FROM recovery_actions ra
        JOIN dues d ON d.id=ra.due_id
        WHERE ra.status='open' AND ra.next_follow_up_at IS NOT NULL
          AND ra.next_follow_up_at<=? AND d.status!='paid'
      )
    ''', [now]);
    final rows = await _db.db.rawQuery('''
      SELECT ra.id action_id,ra.next_follow_up_at,ra.contact_name,
             d.id due_id,(d.amount_due-d.amount_paid) balance,
             s.last_name||' '||s.first_name beneficiary,c.name classroom
      FROM recovery_actions ra
      JOIN dues d ON d.id=ra.due_id
      JOIN students s ON s.id=d.student_id
      LEFT JOIN student_enrollments se ON se.student_id=s.id AND se.school_year_id=d.school_year_id
      LEFT JOIN classrooms c ON c.id=COALESCE(se.classroom_id,s.classroom_id)
      WHERE ra.status='open' AND ra.next_follow_up_at IS NOT NULL
        AND ra.next_follow_up_at<=? AND d.status!='paid'
    ''', [now]);
    var created = 0;
    for (final row in rows) {
      final existing = await _db.db.query(
        'alerts',
        columns: ['id'],
        where: "type='recovery_followup' AND target_id=? AND status!='archived'",
        whereArgs: [row['action_id']],
        limit: 1,
      );
      final values = <String,Object?>{
        'title': 'Relance de recouvrement à effectuer',
        'message': '${row['beneficiary']} · ${row['classroom'] ?? '—'} — ${row['balance']} XAF${row['contact_name'] == null ? '' : ' · ${row['contact_name']}'}',
        'severity': 'high',
      };
      if (existing.isNotEmpty) {
        await _db.db.update('alerts', values, where: 'id=?', whereArgs: [existing.first['id']]);
      } else {
        await _db.db.insert('alerts', {
          'id': _uuid.v4(),
          'type': 'recovery_followup',
          'target_type': 'recovery_action',
          'target_id': row['action_id'],
          ...values,
          'due_at': row['next_follow_up_at'],
          'is_read': 0,
          'status': 'new',
          'notification_sent': 0,
          'created_at': now,
        });
        created++;
      }
    }
    return created;
  }

  Future<int> _refreshUpcomingDues() async {
    final now=DateTime.now();final dueSoonDays=await _intSetting('alert.due_soon_days',3);final limit=now.add(Duration(days:dueSoonDays));final active=await _db.db.query('school_years',columns:['id'],where:'is_active=1',limit:1);final year=active.isEmpty?null:active.first['id'] as String?;
    final rows=await _db.db.rawQuery('''SELECT d.id,d.due_date,(d.amount_due-d.amount_paid) balance,s.last_name||' '||s.first_name beneficiary FROM dues d JOIN students s ON s.id=d.student_id WHERE d.status!='paid' AND d.due_date>=? AND d.due_date<=? ${year==null?'':'AND d.school_year_id=?'}''',[now.toIso8601String(),limit.toIso8601String(),if(year!=null)year]);
    final activeIds=rows.map((r)=>'${r['id']}').toList();
    if(activeIds.isEmpty){await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='due_soon' AND status!='archived'");}
    else{await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='due_soon' AND status!='archived' AND target_id NOT IN (${List.filled(activeIds.length,'?').join(',')})",whereArgs:activeIds);}
    var created=0;
    for(final r in rows){
      final message='${r['beneficiary']} — ${r['balance']} XAF à échéance sous $dueSoonDays jours';
      final existing=await _db.db.query('alerts',columns:['id','status','is_read','message','due_at','notification_sent'],where:"type='due_soon' AND target_id=? AND status!='archived'",whereArgs:[r['id']],limit:1);
      if(existing.isEmpty){await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'due_soon','target_type':'due','target_id':r['id'],'title':'Échéance bientôt due','message':message,'due_at':r['due_date'],'is_read':0,'severity':'warning','status':'new','notification_sent':0,'created_at':now.toIso8601String()});created++;continue;}
      final old=existing.first;final reactivated=old['status']=='resolved';final changed=old['message']!=message||old['due_at']!=r['due_date'];
      await _db.db.update('alerts',{'title':'Échéance bientôt due','message':message,'due_at':r['due_date'],'severity':'warning','status':reactivated?'new':old['status'],'is_read':reactivated?0:old['is_read'],if(reactivated||changed)'notification_sent':0},where:'id=?',whereArgs:[old['id']]);
    }
    return created;
  }

  Future<int> _refreshBackupHealth() async {
    final prefs=await SharedPreferences.getInstance();final staleDays=await _intSetting('alert.backup_stale_days',7);final last=DateTime.tryParse(prefs.getString('gesapp.auto_backup.last_success')??'');final stale=last==null||DateTime.now().difference(last)>Duration(days:staleDays);final existing=await _db.db.query('alerts',columns:['id'],where:"type='backup_health' AND status!='archived'",limit:1);
    if(!stale){if(existing.isNotEmpty)await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:'id=?',whereArgs:[existing.first['id']]);return 0;}
    if(existing.isNotEmpty)return 0;await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'backup_health','target_type':'system','target_id':'backup','title':'Sauvegarde recommandée','message':'Aucune sauvegarde automatique réussie depuis plus de $staleDays jours.','is_read':0,'severity':'high','status':'new','notification_sent':0,'created_at':DateTime.now().toIso8601String()});return 1;
  }

  Future<int> _refreshIntegrityHealth() async {
    final result=await _db.db.rawQuery('PRAGMA integrity_check');final ok=result.isNotEmpty&&result.first.values.first.toString().toLowerCase()=='ok';final existing=await _db.db.query('alerts',columns:['id'],where:"type='integrity_health' AND status!='archived'",limit:1);
    if(ok){if(existing.isNotEmpty)await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:'id=?',whereArgs:[existing.first['id']]);return 0;}
    if(existing.isNotEmpty)return 0;await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'integrity_health','target_type':'system','target_id':'database','title':'Anomalie de base de données','message':'Le contrôle SQLite a signalé une anomalie. Lancez Diagnostic des données.','is_read':0,'severity':'critical','status':'new','notification_sent':0,'created_at':DateTime.now().toIso8601String()});return 1;
  }

  Future<int> _refreshRecurringExpenses() async {
    final now=DateTime.now();final limit=now.add(const Duration(days:3));
    await _db.db.rawUpdate("UPDATE alerts SET is_read=1,status='resolved' WHERE type='recurring_expense' AND status!='archived' AND target_id NOT IN (SELECT id FROM recurring_expense_templates WHERE active=1 AND next_due_at<=?)",[limit.toIso8601String()]);
    final rows=await _db.db.query('recurring_expense_templates',where:'active=1 AND next_due_at<=?',whereArgs:[limit.toIso8601String()],orderBy:'next_due_at');var created=0;
    for(final row in rows){final existing=await _db.db.query('alerts',columns:['id'],where:"type='recurring_expense' AND target_id=? AND status!='archived' AND status!='resolved'",whereArgs:[row['id']],limit:1);if(existing.isNotEmpty)continue;await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'recurring_expense','target_type':'recurring_expense','target_id':row['id'],'title':'Dépense récurrente à préparer','message':'${row['name']} — échéance prévue le ${('${row['next_due_at']}').split('T').first}','due_at':row['next_due_at'],'is_read':0,'severity':'warning','status':'new','notification_sent':0,'created_at':now.toIso8601String()});created++;}
    return created;
  }


  Future<int> _refreshHrContracts() async {
    final now=DateTime.now();final limit=now.add(const Duration(days:30));
    await _db.db.rawUpdate("UPDATE alerts SET is_read=1,status='resolved' WHERE type='hr_contract_expiry' AND status!='archived' AND target_id NOT IN (SELECT id FROM employment_contracts WHERE status='active' AND end_date IS NOT NULL AND end_date>=? AND end_date<=?)",[now.toIso8601String(),limit.toIso8601String()]);
    final rows=await _db.db.rawQuery("SELECT c.id,c.end_date,e.last_name||' '||e.first_name employee_name FROM employment_contracts c JOIN employees e ON e.id=c.employee_id WHERE c.status='active' AND c.end_date IS NOT NULL AND c.end_date>=? AND c.end_date<=?",[now.toIso8601String(),limit.toIso8601String()]);var created=0;
    for(final r in rows){final ex=await _db.db.query('alerts',columns:['id'],where:"type='hr_contract_expiry' AND target_id=? AND status!='archived'",whereArgs:[r['id']],limit:1);if(ex.isNotEmpty)continue;final days=DateTime.parse(r['end_date'] as String).difference(now).inDays;await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'hr_contract_expiry','target_type':'employment_contract','target_id':r['id'],'title':'Contrat RH bientôt expiré','message':'${r['employee_name']} — expiration dans $days jour(s)','due_at':r['end_date'],'is_read':0,'severity':days<=7?'high':'warning','status':'new','notification_sent':0,'created_at':now.toIso8601String()});created++;}return created;
  }

  Future<int> _refreshHrDocuments() async {
    final now=DateTime.now().toIso8601String();
    final rows=await _db.db.rawQuery("SELECT e.id,e.last_name||' '||e.first_name employee_name FROM employees e WHERE e.status='active' AND NOT EXISTS(SELECT 1 FROM employee_documents d WHERE d.employee_id=e.id AND lower(d.document_type) LIKE '%identit%')");var created=0;
    for(final r in rows){final ex=await _db.db.query('alerts',columns:['id'],where:"type='hr_document_missing' AND target_id=? AND status!='archived'",whereArgs:[r['id']],limit:1);if(ex.isNotEmpty)continue;await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'hr_document_missing','target_type':'employee','target_id':r['id'],'title':'Dossier RH incomplet','message':'${r['employee_name']} — pièce d’identité manquante','is_read':0,'severity':'warning','status':'new','notification_sent':0,'created_at':now});created++;}
    final activeIds=rows.map((r)=>'${r['id']}').toList();if(activeIds.isEmpty){await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='hr_document_missing' AND status!='archived'");}else{await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='hr_document_missing' AND status!='archived' AND target_id NOT IN (${List.filled(activeIds.length,'?').join(',')})",whereArgs:activeIds);}return created;
  }

  Future<int> _refreshHrPayroll() async {
    final now=DateTime.now(); if(now.day<20)return 0;final start=DateTime(now.year,now.month,1).toIso8601String();final end=DateTime(now.year,now.month+1,1).toIso8601String();final periods=await _db.db.rawQuery('SELECT id FROM payroll_periods WHERE start_date>=? AND start_date<? LIMIT 1',[start,end]);final existing=await _db.db.query('alerts',columns:['id'],where:"type='hr_payroll_missing' AND status!='archived'",limit:1);
    if(periods.isNotEmpty){if(existing.isNotEmpty)await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:'id=?',whereArgs:[existing.first['id']]);return 0;}if(existing.isNotEmpty)return 0;await _db.db.insert('alerts',{'id':_uuid.v4(),'type':'hr_payroll_missing','target_type':'hr','target_id':'payroll-${now.year}-${now.month}','title':'Paie du mois à préparer','message':'Aucune période de paie n’a encore été créée pour ce mois.','is_read':0,'severity':'high','status':'new','notification_sent':0,'created_at':now.toIso8601String()});return 1;
  }


  Future<int> _refreshAssetWarranties() async {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 30));
    final nowIso = now.toIso8601String();
    await _db.db.rawUpdate(
      "UPDATE alerts SET is_read=1,status='resolved' WHERE type='asset_warranty' AND status!='archived' AND target_id NOT IN (SELECT id FROM assets WHERE status!='disposed' AND warranty_end_date IS NOT NULL AND warranty_end_date>=? AND warranty_end_date<=?)",
      [nowIso, limit.toIso8601String()],
    );
    final rows = await _db.db.rawQuery(
      "SELECT id,asset_number,name,warranty_end_date FROM assets WHERE status!='disposed' AND warranty_end_date IS NOT NULL AND warranty_end_date>=? AND warranty_end_date<=?",
      [nowIso, limit.toIso8601String()],
    );
    var created = 0;
    for (final r in rows) {
      final existing = await _db.db.query('alerts', columns: ['id'], where: "type='asset_warranty' AND target_id=? AND status!='archived'", whereArgs: [r['id']], limit: 1);
      if (existing.isNotEmpty) continue;
      final end = DateTime.parse(r['warranty_end_date'] as String);
      final days = end.difference(now).inDays;
      await _db.db.insert('alerts', {
        'id': _uuid.v4(), 'type': 'asset_warranty', 'target_type': 'asset', 'target_id': r['id'],
        'title': 'Garantie bientôt expirée',
        'message': "${r['asset_number']} · ${r['name']} — expiration dans $days jour(s)",
        'due_at': r['warranty_end_date'], 'is_read': 0, 'severity': days <= 7 ? 'high' : 'warning',
        'status': 'new', 'notification_sent': 0, 'created_at': nowIso,
      });
      created++;
    }
    return created;
  }

  Future<int> _refreshAssetMaintenance() async {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));
    final nowIso = now.toIso8601String();
    await _db.db.rawUpdate(
      "UPDATE alerts SET is_read=1,status='resolved' WHERE type='asset_maintenance_due' AND status!='archived' AND target_id NOT IN (SELECT id FROM asset_maintenance WHERE next_maintenance_at IS NOT NULL AND next_maintenance_at<=? AND status!='cancelled')",
      [limit.toIso8601String()],
    );
    final rows = await _db.db.rawQuery(
      "SELECT m.id,m.next_maintenance_at,a.asset_number,a.name FROM asset_maintenance m JOIN assets a ON a.id=m.asset_id WHERE m.next_maintenance_at IS NOT NULL AND m.next_maintenance_at<=? AND m.status!='cancelled' AND a.status!='disposed'",
      [limit.toIso8601String()],
    );
    var created = 0;
    for (final r in rows) {
      final existing = await _db.db.query('alerts', columns: ['id'], where: "type='asset_maintenance_due' AND target_id=? AND status!='archived'", whereArgs: [r['id']], limit: 1);
      if (existing.isNotEmpty) continue;
      final dueLabel = r['next_maintenance_at'].toString().split('T').first;
      await _db.db.insert('alerts', {
        'id': _uuid.v4(), 'type': 'asset_maintenance_due', 'target_type': 'asset_maintenance', 'target_id': r['id'],
        'title': 'Maintenance patrimoniale à prévoir',
        'message': "${r['asset_number']} · ${r['name']} — intervention prévue le $dueLabel",
        'due_at': r['next_maintenance_at'], 'is_read': 0, 'severity': 'warning', 'status': 'new',
        'notification_sent': 0, 'created_at': nowIso,
      });
      created++;
    }
    return created;
  }

  Future<int> _refreshAssetInventory() async {
    final now = DateTime.now();
    final threshold = now.subtract(const Duration(days: 30)).toIso8601String();
    final rows = await _db.db.rawQuery("SELECT id,label,started_at FROM asset_inventory_sessions WHERE status='open' AND started_at<?", [threshold]);
    var created = 0;
    for (final r in rows) {
      final existing = await _db.db.query('alerts', columns: ['id'], where: "type='asset_inventory_open' AND target_id=? AND status!='archived'", whereArgs: [r['id']], limit: 1);
      if (existing.isNotEmpty) continue;
      await _db.db.insert('alerts', {
        'id': _uuid.v4(), 'type': 'asset_inventory_open', 'target_type': 'asset_inventory', 'target_id': r['id'],
        'title': 'Inventaire patrimonial non clôturé', 'message': "${r['label']} est ouvert depuis plus de 30 jours.",
        'is_read': 0, 'severity': 'high', 'status': 'new', 'notification_sent': 0, 'created_at': now.toIso8601String(),
      });
      created++;
    }
    final activeIds=rows.map((r)=>'${r['id']}').toList();
    if(activeIds.isEmpty){await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='asset_inventory_open' AND status!='archived'");}
    else{await _db.db.update('alerts',{'is_read':1,'status':'resolved'},where:"type='asset_inventory_open' AND status!='archived' AND target_id NOT IN (${List.filled(activeIds.length,'?').join(',')})",whereArgs:activeIds);}
    return created;
  }

  Future<List<Map<String,Object?>>> list({bool unreadOnly=false})=>_db.db.query('alerts',where:unreadOnly?"is_read=0 AND status!='archived'":"status!='archived'",orderBy:"CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END,is_read ASC,created_at DESC");
  Future<void> markRead(String id)=>_db.db.update('alerts',{'is_read':1,'status':'seen'},where:'id=?',whereArgs:[id]);
  Future<void> markAllRead()=>_db.db.update('alerts',{'is_read':1,'status':'seen'},where:"is_read=0 AND status!='archived'");
  Future<void> archive(String id)=>_db.db.update('alerts',{'status':'archived','is_read':1},where:'id=?',whereArgs:[id]);
}
