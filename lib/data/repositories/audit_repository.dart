import '../../core/db/app_database.dart';

class AuditEntry {
  const AuditEntry({required this.entityType,required this.entityId,required this.action,required this.createdAt,required this.operatorName,this.oldValue,this.newValue});
  final String entityType,entityId,action,operatorName;final DateTime createdAt;final String? oldValue,newValue;
}
class AuditRepository {
  AuditRepository(this._database);final AppDatabase _database;
  Future<List<AuditEntry>> search({String query='',String? entityType,String? action,DateTime? from,DateTime? to,int limit=100,int offset=0}) async {
    final where=<String>[];final args=<Object?>[];final q=query.trim();
    if(q.isNotEmpty){where.add('(entity_id LIKE ? OR operator_name LIKE ? OR old_value LIKE ? OR new_value LIKE ?)');args.addAll(List.filled(4,'%$q%'));}
    if(entityType!=null&&entityType.isNotEmpty){where.add('entity_type=?');args.add(entityType);}if(action!=null&&action.isNotEmpty){where.add('action=?');args.add(action);}if(from!=null){where.add('created_at>=?');args.add(from.toIso8601String());}if(to!=null){where.add('created_at<=?');args.add(to.toIso8601String());}
    final rows=await _database.db.query('audit_log',where:where.isEmpty?null:where.join(' AND '),whereArgs:args,orderBy:'created_at DESC,id DESC',limit:limit,offset:offset);
    return rows.map((r)=>AuditEntry(entityType:r['entity_type'] as String,entityId:r['entity_id'] as String,action:r['action'] as String,oldValue:r['old_value'] as String?,newValue:r['new_value'] as String?,operatorName:(r['operator_name'] as String?)??'Gestionnaire',createdAt:DateTime.parse(r['created_at'] as String))).toList();
  }
  Future<List<AuditEntry>> recent({int limit=300})=>search(limit:limit);
}
