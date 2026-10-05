import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';
import 'cash_rules.dart';
import '../models/asset.dart';

class AssetRepository {
  AssetRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<void> _audit(DatabaseExecutor db, String type, String id, String action, String value) => db.insert('audit_log', {
        'entity_type': type,
        'entity_id': id,
        'action': action,
        'new_value': value,
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': DateTime.now().toIso8601String(),
      });

  Future<AssetSummary> summary() async {
    final db = _database.db;
    final total = firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM assets WHERE status!='disposed'")) ?? 0;
    final inService = firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM assets WHERE status='in_service'")) ?? 0;
    final maintenance = firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM assets WHERE status='maintenance'")) ?? 0;
    final out = firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM assets WHERE status='out_of_service'")) ?? 0;
    final missing = firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM assets WHERE status='missing'")) ?? 0;
    final value = firstIntValue(await db.rawQuery("SELECT COALESCE(SUM(acquisition_value),0) FROM assets WHERE status!='disposed'")) ?? 0;
    final now = DateTime.now();
    final in30 = now.add(const Duration(days: 30));
    final warranty = firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM assets WHERE status!='disposed' AND warranty_end_date IS NOT NULL AND warranty_end_date>=? AND warranty_end_date<=?",
          [now.toIso8601String(), in30.toIso8601String()],
        )) ??
        0;
    final openInv = firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM asset_inventory_sessions WHERE status='open'")) ?? 0;
    return AssetSummary(total: total, inService: inService, maintenance: maintenance, outOfService: out, missing: missing, totalAcquisitionValue: value, warrantyExpiring: warranty, openInventories: openInv);
  }

  Future<List<AssetCategoryItem>> categories({bool activeOnly = true}) async {
    final rows = await _database.db.query('asset_categories', where: activeOnly ? 'active=1' : null, orderBy: 'name');
    return rows
        .map((r) => AssetCategoryItem(id: r['id'] as String, name: r['name'] as String, description: r['description'] as String?, active: (r['active'] as int) == 1))
        .toList();
  }

  Future<void> saveCategory({
    String? id, required String name, String? description, bool active = true}) async {
      BusinessWriteGuard.ensureAllowed('saveCategory');
      
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Le nom de la catégorie est obligatoire.');
    final key = id ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final data = {'name': clean, 'description': description?.trim(), 'active': active ? 1 : 0, 'updated_at': now};
      if (id == null) {
        await txn.insert('asset_categories', {'id': key, ...data, 'created_at': now});
      } else {
        await txn.update('asset_categories', data, where: 'id=?', whereArgs: [id]);
      }
      await _audit(txn, 'asset_category', key, id == null ? 'create' : 'update', clean);
    });
  }

  Future<List<AssetLocationItem>> locations({bool activeOnly = true}) async {
    final rows = await _database.db.rawQuery('''
      SELECT l.*,p.name parent_name FROM asset_locations l
      LEFT JOIN asset_locations p ON p.id=l.parent_id
      ${activeOnly ? 'WHERE l.active=1' : ''}
      ORDER BY COALESCE(p.name,''),l.type,l.name
    ''');
    return rows
        .map((r) => AssetLocationItem(
              id: r['id'] as String,
              name: r['name'] as String,
              type: r['type'] as String,
              active: (r['active'] as int) == 1,
              parentId: r['parent_id'] as String?,
              parentName: r['parent_name'] as String?,
              description: r['description'] as String?,
            ))
        .toList();
  }

  Future<void> saveLocation({
    String? id, required String name, required String type, String? parentId, String? description, bool active = true}) async {
      BusinessWriteGuard.ensureAllowed('saveLocation');
      
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('Le nom de la localisation est obligatoire.');
    if (!['site', 'building', 'floor', 'room', 'store'].contains(type)) throw ArgumentError('Type de localisation invalide.');
    if (id != null && id == parentId) throw StateError('Une localisation ne peut pas être son propre parent.');
    final key = id ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final data = {'name': clean, 'type': type, 'parent_id': parentId, 'description': description?.trim(), 'active': active ? 1 : 0, 'updated_at': now};
      if (id == null) {
        await txn.insert('asset_locations', {'id': key, ...data, 'created_at': now});
      } else {
        await txn.update('asset_locations', data, where: 'id=?', whereArgs: [id]);
      }
      await _audit(txn, 'asset_location', key, id == null ? 'create' : 'update', clean);
    });
  }

  Future<List<AssetItem>> assets({String query = '', String? status, String? categoryId, int limit = 100, int offset = 0}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (status != null && status.isNotEmpty) { where.add('a.status=?'); args.add(status); }
    if (categoryId != null && categoryId.isNotEmpty) { where.add('a.category_id=?'); args.add(categoryId); }
    if (query.trim().isNotEmpty) {
      where.add('(a.asset_number LIKE ? OR a.name LIKE ? OR a.brand LIKE ? OR a.model LIKE ? OR a.serial_number LIKE ? OR l.name LIKE ? OR e.first_name LIKE ? OR e.last_name LIKE ?)');
      args.addAll(List.filled(8, '%${query.trim()}%'));
    }
    args.addAll([limit, offset]);
    final rows = await _database.db.rawQuery('''
      SELECT a.*,c.name category_name,l.name location_name,
        CASE WHEN e.id IS NULL THEN NULL ELSE e.last_name||' '||e.first_name END employee_name
      FROM assets a
      JOIN asset_categories c ON c.id=a.category_id
      LEFT JOIN asset_locations l ON l.id=a.current_location_id
      LEFT JOIN employees e ON e.id=a.current_employee_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY a.name,a.asset_number LIMIT ? OFFSET ?
    ''', args);
    return rows.map(_assetFromRow).toList();
  }

  AssetItem _assetFromRow(Map<String, Object?> r) => AssetItem(
        id: r['id'] as String,
        assetNumber: r['asset_number'] as String,
        name: r['name'] as String,
        categoryId: r['category_id'] as String,
        categoryName: r['category_name'] as String,
        condition: r['condition'] as String,
        status: r['status'] as String,
        acquisitionValue: (r['acquisition_value'] as num).toInt(),
        brand: r['brand'] as String?,
        model: r['model'] as String?,
        serialNumber: r['serial_number'] as String?,
        locationId: r['current_location_id'] as String?,
        locationName: r['location_name'] as String?,
        employeeId: r['current_employee_id'] as String?,
        employeeName: r['employee_name'] as String?,
        photoPath: r['photo_path'] as String?,
        warrantyEndDate: r['warranty_end_date'] == null ? null : DateTime.tryParse(r['warranty_end_date'] as String),
      );

  Future<String> nextAssetNumber() async {
    final year = DateTime.now().year;
    final maxValue = firstIntValue(await _database.db.rawQuery("SELECT COALESCE(MAX(CAST(substr(asset_number,10) AS INTEGER)),0) FROM assets WHERE asset_number LIKE ?", ['PAT-$year-%'])) ?? 0;
    return 'PAT-$year-${(maxValue + 1).toString().padLeft(5, '0')}';
  }

  Future<String> saveAsset({
    String? id,
    required String name,
    required String categoryId,
    String? assetNumber,
    String? brand,
    String? model,
    String? serialNumber,
    DateTime? acquisitionDate,
    int acquisitionValue = 0,
    String acquisitionMethod = 'purchase',
    String? supplier,
    String? locationId,
    String? employeeId,
    String condition = 'good',
    String status = 'in_service',
    DateTime? warrantyEndDate,
    String? photoPath,
    String? purchaseProofPath,
    String? notes,
  }) async {
    BusinessWriteGuard.ensureAllowed('saveAsset');
    if (name.trim().isEmpty) throw ArgumentError('La désignation est obligatoire.');
    if (acquisitionValue < 0) throw ArgumentError('La valeur d’acquisition ne peut pas être négative.');
    final normalizedStatus = status == 'retired' ? 'out_of_service' : status;
    const allowedStatuses = {'in_service','stock','maintenance','out_of_service','missing','disposed'};
    if (!allowedStatuses.contains(normalizedStatus)) throw ArgumentError('Statut patrimoine invalide.');
    final key = id ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final number = (assetNumber ?? '').trim().isEmpty ? await nextAssetNumber() : assetNumber!.trim();
    await _database.db.transaction((txn) async {
      if (id != null) {
        final currentRows = await txn.query('assets', columns: ['status'], where: 'id=?', whereArgs: [id], limit: 1);
        if (currentRows.isEmpty) throw StateError('Bien introuvable.');
        if (currentRows.first['status'] == 'disposed' && normalizedStatus != 'disposed') {
          throw StateError('Un bien sorti du patrimoine ne peut pas être réactivé par modification.');
        }
      }
      final data = <String, Object?>{
        'asset_number': number,
        'category_id': categoryId,
        'name': name.trim(),
        'brand': brand?.trim(),
        'model': model?.trim(),
        'serial_number': serialNumber?.trim(),
        'acquisition_date': acquisitionDate?.toIso8601String(),
        'acquisition_value': acquisitionValue,
        'acquisition_method': acquisitionMethod,
        'supplier': supplier?.trim(),
        'current_location_id': locationId,
        'current_employee_id': employeeId,
        'condition': condition,
        'status': normalizedStatus,
        'warranty_end_date': warrantyEndDate?.toIso8601String(),
        'photo_path': photoPath,
        'purchase_proof_path': purchaseProofPath,
        'notes': notes?.trim(),
        'updated_at': now,
      };
      if (id == null) {
        await txn.insert('assets', {'id': key, ...data, 'created_at': now});
        await txn.insert('asset_movements', {
          'id': _uuid.v4(), 'asset_id': key, 'movement_type': 'acquisition',
          'to_location_id': locationId, 'to_employee_id': employeeId, 'moved_at': now,
          'reason': 'Entrée initiale au patrimoine', 'condition_after': condition,
          'operator_id': OperatorSession.userId, 'created_at': now,
        });
        if (employeeId != null || locationId != null) {
          await txn.insert('asset_assignments', {
            'id': _uuid.v4(), 'asset_id': key, 'employee_id': employeeId, 'location_id': locationId,
            'assigned_at': now, 'condition_at_assignment': condition, 'notes': 'Affectation initiale',
            'operator_id': OperatorSession.userId, 'created_at': now,
          });
        }
      } else {
        await txn.update('assets', data, where: 'id=?', whereArgs: [id]);
      }
      await _audit(txn, 'asset', key, id == null ? 'create' : 'update', '$number · ${name.trim()}');
    });
    return key;
  }

  Future<void> moveAsset({
    required String assetId, String? toLocationId, String? toEmployeeId, required String movementType, String? reason, String? conditionAfter}) async {
      BusinessWriteGuard.ensureAllowed('moveAsset');
      
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows = await txn.query('assets', where: 'id=?', whereArgs: [assetId], limit: 1);
      if (rows.isEmpty) throw StateError('Bien introuvable.');
      final asset = rows.first;
      if (asset['status'] == 'disposed') throw StateError('Un bien sorti du patrimoine ne peut plus être déplacé.');
      await txn.update('asset_assignments', {
        'returned_at': now,
        'condition_at_return': conditionAfter ?? asset['condition'],
      }, where: 'asset_id=? AND returned_at IS NULL', whereArgs: [assetId]);
      if (toEmployeeId != null || toLocationId != null) {
        await txn.insert('asset_assignments', {
          'id': _uuid.v4(), 'asset_id': assetId, 'employee_id': toEmployeeId, 'location_id': toLocationId,
          'assigned_at': now, 'condition_at_assignment': conditionAfter ?? asset['condition'],
          'notes': reason?.trim(), 'operator_id': OperatorSession.userId, 'created_at': now,
        });
      }
      await txn.insert('asset_movements', {
        'id': _uuid.v4(), 'asset_id': assetId, 'movement_type': movementType,
        'from_location_id': asset['current_location_id'], 'to_location_id': toLocationId,
        'from_employee_id': asset['current_employee_id'], 'to_employee_id': toEmployeeId,
        'moved_at': now, 'reason': reason?.trim(), 'condition_after': conditionAfter,
        'operator_id': OperatorSession.userId, 'created_at': now,
      });
      await txn.update('assets', {
        'current_location_id': toLocationId,
        'current_employee_id': toEmployeeId,
        if (conditionAfter != null) 'condition': conditionAfter,
        'updated_at': now,
      }, where: 'id=?', whereArgs: [assetId]);
      await _audit(txn, 'asset', assetId, 'move', movementType);
    });
  }

  Future<List<Map<String, Object?>>> movements(String assetId) => _database.db.rawQuery('''
    SELECT m.*,fl.name from_location,tl.name to_location,
      CASE WHEN fe.id IS NULL THEN NULL ELSE fe.last_name||' '||fe.first_name END from_employee,
      CASE WHEN te.id IS NULL THEN NULL ELSE te.last_name||' '||te.first_name END to_employee
    FROM asset_movements m
    LEFT JOIN asset_locations fl ON fl.id=m.from_location_id
    LEFT JOIN asset_locations tl ON tl.id=m.to_location_id
    LEFT JOIN employees fe ON fe.id=m.from_employee_id
    LEFT JOIN employees te ON te.id=m.to_employee_id
    WHERE m.asset_id=? ORDER BY m.moved_at DESC
  ''', [assetId]);

  Future<List<AssetMaintenanceItem>> maintenance({String? assetId, String? status}) async {
    final where = <String>[]; final args = <Object?>[];
    if (assetId != null) { where.add('m.asset_id=?'); args.add(assetId); }
    if (status != null) { where.add('m.status=?'); args.add(status); }
    final rows = await _database.db.rawQuery('''SELECT m.*,a.asset_number||' · '||a.name asset_name FROM asset_maintenance m JOIN assets a ON a.id=m.asset_id ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY m.started_at DESC''', args);
    return rows.map((r) => AssetMaintenanceItem(
      id:r['id'] as String, assetId:r['asset_id'] as String, assetName:r['asset_name'] as String,
      type:r['maintenance_type'] as String, status:r['status'] as String, cost:(r['cost'] as num).toInt(),
      startedAt:DateTime.parse(r['started_at'] as String), nextMaintenanceAt:r['next_maintenance_at']==null?null:DateTime.tryParse(r['next_maintenance_at'] as String),
      provider:r['provider'] as String?, problem:r['problem'] as String?, expenseId:r['expense_id'] as String?,
    )).toList();
  }

  Future<String> saveMaintenance({
    String? id, required String assetId, required String maintenanceType, String? problem, String? diagnosis, String? provider, int cost = 0, DateTime? startedAt, DateTime? completedAt, DateTime? nextMaintenanceAt, String? proofPath, String status = 'planned', String? notes}) async {
      BusinessWriteGuard.ensureAllowed('saveMaintenance');
      
    if (cost < 0) throw ArgumentError('Coût invalide.');
    final key=id??_uuid.v4(), now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final assetRows=await txn.query('assets',columns:['status'],where:'id=?',whereArgs:[assetId],limit:1);
      if(assetRows.isEmpty) throw StateError('Bien introuvable.');
      final currentStatus='${assetRows.first['status']}';
      if(!{'in_service','stock','maintenance'}.contains(currentStatus)) {
        throw StateError('Ce bien ($currentStatus) ne peut pas recevoir une intervention de maintenance.');
      }
      final data=<String,Object?>{'asset_id':assetId,'maintenance_type':maintenanceType,'problem':problem?.trim(),'diagnosis':diagnosis?.trim(),'provider':provider?.trim(),'cost':cost,'started_at':(startedAt??DateTime.now()).toIso8601String(),'completed_at':completedAt?.toIso8601String(),'next_maintenance_at':nextMaintenanceAt?.toIso8601String(),'proof_path':proofPath,'status':status,'notes':notes?.trim(),'updated_at':now};
      if(id==null){await txn.insert('asset_maintenance',{'id':key,...data,'created_at':now});}else{await txn.update('asset_maintenance',data,where:'id=?',whereArgs:[id]);}
      if(status=='in_progress') {
        await txn.update('assets',{'status':'maintenance','updated_at':now},where:'id=?',whereArgs:[assetId]);
      } else if(status=='completed') {
        await txn.update('assets',{'status':'in_service','updated_at':now},where:'id=?',whereArgs:[assetId]);
      }
      await _audit(txn,'asset_maintenance',key,id==null?'create':'update','$maintenanceType/$cost');
    });
    return key;
  }

  Future<List<AssetInventorySessionItem>> inventorySessions() async {
    final rows=await _database.db.rawQuery('''SELECT s.*,COUNT(i.id) total,SUM(CASE WHEN i.result!='not_checked' THEN 1 ELSE 0 END) checked,SUM(CASE WHEN i.result='missing' THEN 1 ELSE 0 END) missing,SUM(CASE WHEN i.result='damaged' THEN 1 ELSE 0 END) damaged FROM asset_inventory_sessions s LEFT JOIN asset_inventory_items i ON i.session_id=s.id GROUP BY s.id ORDER BY s.started_at DESC''');
    return rows.map((r)=>AssetInventorySessionItem(id:r['id'] as String,label:r['label'] as String,startedAt:DateTime.parse(r['started_at'] as String),status:r['status'] as String,total:(r['total'] as num).toInt(),checked:((r['checked'] as num?)??0).toInt(),missing:((r['missing'] as num?)??0).toInt(),damaged:((r['damaged'] as num?)??0).toInt())).toList();
  }

  Future<String> startInventory({
    required String label,String? locationId,String? notes}) async {
      BusinessWriteGuard.ensureAllowed('startInventory');
      
    final id=_uuid.v4(),now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.insert('asset_inventory_sessions',{'id':id,'label':label.trim(),'started_at':now,'location_id':locationId,'status':'open','notes':notes?.trim(),'created_by':OperatorSession.userId,'created_at':now});
      final assets=await txn.query('assets',columns:['id'],where:locationId==null?"status!='disposed'":"status!='disposed' AND current_location_id=?",whereArgs:locationId==null?null:[locationId]);
      for(final a in assets){await txn.insert('asset_inventory_items',{'id':_uuid.v4(),'session_id':id,'asset_id':a['id'],'result':'not_checked'});}
      await _audit(txn,'asset_inventory',id,'create',label);
    });
    return id;
  }

  Future<List<Map<String,Object?>>> inventoryItems(String sessionId) => _database.db.rawQuery('''SELECT i.*,a.asset_number,a.name,l.name expected_location FROM asset_inventory_items i JOIN assets a ON a.id=i.asset_id LEFT JOIN asset_locations l ON l.id=a.current_location_id WHERE i.session_id=? ORDER BY a.name''',[sessionId]);

  Future<void> checkInventoryItem({
    required String itemId,required String result,String? observedLocationId,String? observedCondition,String? note}) async {
      BusinessWriteGuard.ensureAllowed('checkInventoryItem');
      
    if(!['found','missing','moved','damaged'].contains(result)) throw ArgumentError('Résultat invalide.');
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      final rows=await txn.rawQuery('''SELECT i.*,s.status session_status FROM asset_inventory_items i JOIN asset_inventory_sessions s ON s.id=i.session_id WHERE i.id=? LIMIT 1''',[itemId]);if(rows.isEmpty)throw StateError('Ligne d’inventaire introuvable.');
      if(rows.first['session_status']!='open') throw StateError('Cet inventaire est clôturé et ne peut plus être modifié.');
      final assetId=rows.first['asset_id'] as String;
      await txn.update('asset_inventory_items',{'result':result,'observed_location_id':observedLocationId,'observed_condition':observedCondition,'note':note?.trim(),'checked_at':now,'checked_by':OperatorSession.userId},where:'id=?',whereArgs:[itemId]);
      if(result=='missing') await txn.update('assets',{'status':'missing','updated_at':now},where:'id=?',whereArgs:[assetId]);
      if(result=='found') {
        final current=await txn.query('assets',columns:['status'],where:'id=?',whereArgs:[assetId],limit:1);
        if(current.isNotEmpty&&current.first['status']=='missing') await txn.update('assets',{'status':'in_service','updated_at':now},where:'id=?',whereArgs:[assetId]);
      }
      if(result=='damaged'&&observedCondition!=null) await txn.update('assets',{'condition':observedCondition,'updated_at':now},where:'id=?',whereArgs:[assetId]);
      if(result=='moved'&&observedLocationId!=null) {
        final current=await txn.query('assets',columns:['current_location_id','current_employee_id','condition'],where:'id=?',whereArgs:[assetId],limit:1);
        await txn.insert('asset_movements',{'id':_uuid.v4(),'asset_id':assetId,'movement_type':'inventory_adjustment','from_location_id':current.first['current_location_id'],'to_location_id':observedLocationId,'from_employee_id':current.first['current_employee_id'],'to_employee_id':current.first['current_employee_id'],'moved_at':now,'reason':'Correction lors de l’inventaire','condition_after':observedCondition??current.first['condition'],'operator_id':OperatorSession.userId,'created_at':now});
        await txn.update('assets',{'current_location_id':observedLocationId,'updated_at':now},where:'id=?',whereArgs:[assetId]);
      }
    });
  }

  Future<void> completeInventory(String sessionId) async {
    BusinessWriteGuard.ensureAllowed('completeInventory');
    final sessionRows=await _database.db.query('asset_inventory_sessions',columns:['status'],where:'id=?',whereArgs:[sessionId],limit:1);
    if(sessionRows.isEmpty) throw StateError('Inventaire introuvable.');
    if(sessionRows.first['status']!='open') throw StateError('Cet inventaire est déjà clôturé.');
    final remaining=firstIntValue(await _database.db.rawQuery("SELECT COUNT(*) FROM asset_inventory_items WHERE session_id=? AND result='not_checked'",[sessionId]))??0;
    if(remaining>0) throw StateError('$remaining bien(s) ne sont pas encore vérifiés.');
    final now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn)async{await txn.update('asset_inventory_sessions',{'status':'completed','completed_at':now},where:'id=?',whereArgs:[sessionId]);await _audit(txn,'asset_inventory',sessionId,'complete','Inventaire clôturé');});
  }

  Future<void> disposeAsset({
    required String assetId,required String disposalType,required DateTime disposalDate,int saleAmount=0,String? cashAccountId,String? reference,String? reason,String? documentPath}) async {
    BusinessWriteGuard.ensureAllowed('disposeAsset');
    if(saleAmount<0) throw ArgumentError('Montant invalide.');
    if(disposalType=='sale' && (saleAmount<=0 || cashAccountId==null || cashAccountId.trim().isEmpty)) {
      throw ArgumentError('Une vente exige un montant positif et un compte d’encaissement.');
    }
    final id=_uuid.v4(),now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn)async{
      final assetRows=await txn.query('assets',columns:['asset_number','name','status'],where:'id=?',whereArgs:[assetId],limit:1);
      if(assetRows.isEmpty) throw StateError('Bien introuvable.');
      if(assetRows.first['status']=='disposed') throw StateError('Ce bien est déjà sorti du patrimoine.');
      if(disposalType=='sale') await ensureCashMovementAllowed(txn,cashAccountId);
      final ref=(reference??'').trim().isEmpty?'CESS-${assetRows.first['asset_number']}':reference!.trim();
      await txn.insert('asset_disposals',{'id':id,'asset_id':assetId,'disposal_type':disposalType,'disposal_date':disposalDate.toIso8601String(),'sale_amount':saleAmount,'cash_account_id':disposalType=='sale'?cashAccountId:null,'reference':disposalType=='sale'?ref:null,'reason':reason?.trim(),'document_path':documentPath,'operator_id':OperatorSession.userId,'created_at':now});
      if(disposalType=='sale') {
        final accountRows=await txn.query('cash_accounts',columns:['type'],where:'id=?',whereArgs:[cashAccountId],limit:1);
        final type=accountRows.isEmpty?null:accountRows.first['type'] as String?;
        final treasury=switch(type){'bank'=>'521000','mobile'=>'531000',_=>'571000'};
        final journal=switch(type){'bank'=>'BQ','mobile'=>'MM',_=>'CA'};
        final entryId='asset_sale:$id';
        final description='Cession patrimoine — ${assetRows.first['asset_number']} · ${assetRows.first['name']}';
        await txn.insert('accounting_entries',{'id':entryId,'journal_code':journal,'entry_date':disposalDate.toIso8601String(),'reference':ref,'description':description,'source_type':'asset_sale','source_id':id,'status':'posted','created_at':now});
        await txn.insert('accounting_entry_lines',{'id':_uuid.v4(),'entry_id':entryId,'account_code':treasury,'label':description,'debit':saleAmount,'credit':0,'line_order':1});
        await txn.insert('accounting_entry_lines',{'id':_uuid.v4(),'entry_id':entryId,'account_code':'775100','label':description,'debit':0,'credit':saleAmount,'line_order':2});
      }
      await txn.update('assets',{'status':'disposed','current_employee_id':null,'updated_at':now},where:'id=?',whereArgs:[assetId]);
      await _audit(txn,'asset',assetId,'dispose','$disposalType/$saleAmount');
    });
  }
  Future<Map<String,Object?>?> assetDetails(String id) async {
    final rows=await _database.db.rawQuery('''SELECT a.*,c.name category_name,l.name location_name,CASE WHEN e.id IS NULL THEN NULL ELSE e.last_name||' '||e.first_name END employee_name FROM assets a JOIN asset_categories c ON c.id=a.category_id LEFT JOIN asset_locations l ON l.id=a.current_location_id LEFT JOIN employees e ON e.id=a.current_employee_id WHERE a.id=? LIMIT 1''',[id]);
    return rows.isEmpty?null:rows.first;
  }

  Future<List<Map<String,Object?>>> employeeOptions() => _database.db.rawQuery("SELECT id,last_name||' '||first_name name FROM employees WHERE status='active' ORDER BY last_name,first_name");

  Future<List<Map<String,Object?>>> documents(String assetId) => _database.db.query('asset_documents',where:'asset_id=?',whereArgs:[assetId],orderBy:'added_at DESC');

  Future<void> addDocument({
    required String assetId,required String documentType,required String filePath}) async {
      BusinessWriteGuard.ensureAllowed('addDocument');
      
    final id=_uuid.v4(),now=DateTime.now().toIso8601String();
    await _database.db.transaction((txn)async{await txn.insert('asset_documents',{'id':id,'asset_id':assetId,'document_type':documentType.trim(),'file_path':filePath,'added_at':now});await _audit(txn,'asset_document',id,'create',documentType);});
  }

  Future<void> removeDocument(String id) async {
    BusinessWriteGuard.ensureAllowed('removeDocument');
    await _database.db.transaction((txn)async{await txn.delete('asset_documents',where:'id=?',whereArgs:[id]);await _audit(txn,'asset_document',id,'delete','Suppression document');});
  }

  Future<List<Map<String,Object?>>> reportByCategory() => _database.db.rawQuery('''SELECT c.name label,COUNT(a.id) count,COALESCE(SUM(a.acquisition_value),0) total_value FROM asset_categories c LEFT JOIN assets a ON a.category_id=c.id AND a.status!='disposed' GROUP BY c.id,c.name ORDER BY total_value DESC,c.name''');
  Future<List<Map<String,Object?>>> reportByLocation() => _database.db.rawQuery('''SELECT COALESCE(l.name,'Non localisé') label,COUNT(a.id) count,COALESCE(SUM(a.acquisition_value),0) total_value FROM assets a LEFT JOIN asset_locations l ON l.id=a.current_location_id WHERE a.status!='disposed' GROUP BY l.id,l.name ORDER BY count DESC''');
  Future<List<Map<String,Object?>>> reportByStatus() => _database.db.rawQuery("SELECT status label,COUNT(*) count,COALESCE(SUM(acquisition_value),0) total_value FROM assets GROUP BY status ORDER BY count DESC");

  Future<String> createMaintenanceExpense(String maintenanceId) async {
    BusinessWriteGuard.ensureAllowed('createMaintenanceExpense');
    final db=_database.db;
    final rows=await db.rawQuery('''SELECT m.*,a.asset_number,a.name asset_name FROM asset_maintenance m JOIN assets a ON a.id=m.asset_id WHERE m.id=? LIMIT 1''',[maintenanceId]);
    if(rows.isEmpty) throw StateError('Maintenance introuvable.');
    final m=rows.first;
    if(m['expense_id']!=null) return m['expense_id'] as String;
    final cost=(m['cost'] as num).toInt();
    if(cost<=0) throw StateError('La maintenance ne possède aucun coût à comptabiliser.');
    final now=DateTime.now().toIso8601String();
    final cats=await db.query('expense_categories',columns:['id'],where:"lower(name) LIKE '%entretien%' OR lower(name) LIKE '%maintenance%'",limit:1);
    String categoryId;
    if(cats.isEmpty){categoryId=_uuid.v4();await db.insert('expense_categories',{'id':categoryId,'name':'Entretien / Maintenance','active':1});}else{categoryId=cats.first['id'] as String;}
    final count=firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM expenses WHERE expense_number LIKE ?",['DEP-${DateTime.now().year}-%']))??0;
    final expenseId=_uuid.v4();
    final number='DEP-${DateTime.now().year}-${(count+1).toString().padLeft(6,'0')}';
    await db.transaction((txn)async{
      await txn.insert('expenses',{'id':expenseId,'category_id':categoryId,'amount':cost,'spent_at':m['completed_at']??m['started_at']??now,'description':'Maintenance ${m['asset_number']} · ${m['asset_name']}','proof_path':m['proof_path'],'expense_number':number,'beneficiary':m['provider'],'payment_method':null,'cash_account_id':null,'external_reference':null,'approval_status':'pending','submitted_by':OperatorSession.userId,'submitted_at':now,'reviewed_by':null,'reviewed_at':null,'approval_note':'Créée depuis le module Patrimoine','status':'posted','created_at':now});
      await txn.update('asset_maintenance',{'expense_id':expenseId,'updated_at':now},where:'id=?',whereArgs:[maintenanceId]);
      await _audit(txn,'asset_maintenance',maintenanceId,'create_expense',number);
    });
    return expenseId;
  }

}
