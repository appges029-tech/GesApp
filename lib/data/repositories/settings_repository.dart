import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/session/business_write_guard.dart';
import '../../core/session/operator_session.dart';

class EstablishmentData {
  const EstablishmentData({
    required this.name,
    required this.schoolYearLabel,
    required this.schoolYearStart,
    required this.schoolYearEnd,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.approvalNumber = '',
    this.logoPath = '',
  });
  final String name;
  final String schoolYearLabel;
  final DateTime schoolYearStart;
  final DateTime schoolYearEnd;
  final String phone;
  final String email;
  final String address;
  final String approvalNumber;
  final String logoPath;
}

class SchoolYearItem {
  const SchoolYearItem({
    required this.id,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });
  final String id;
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;
}


class PaymentMethodSetting {
  const PaymentMethodSetting({
    required this.id,
    required this.name,
    required this.requiresReference,
    required this.accountType,
    required this.active,
  });

  final String id;
  final String name;
  final bool requiresReference;
  final String accountType;
  final bool active;
}

class CashAccountSetting {
  const CashAccountSetting({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
    required this.active,
  });

  final String id;
  final String name;
  final String type;
  final int openingBalance;
  final bool active;
}


class DocumentRequirementSetting {
  const DocumentRequirementSetting({required this.id, required this.name, required this.required, required this.active, required this.sortOrder, this.description});
  final String id;
  final String name;
  final String? description;
  final bool required;
  final bool active;
  final int sortOrder;
}

class SettingsRepository {
  SettingsRepository(this._database);
  final AppDatabase _database;
  static const _uuid = Uuid();

  Future<EstablishmentData?> establishment() async {
    final rows = await _database.db.query('establishments', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return EstablishmentData(
      name: row['name'] as String,
      schoolYearLabel: row['school_year_label'] as String,
      schoolYearStart: DateTime.parse(row['school_year_start'] as String),
      schoolYearEnd: DateTime.parse(row['school_year_end'] as String),
      phone: (row['phone'] as String?) ?? '',
      email: (row['email'] as String?) ?? '',
      address: (row['address'] as String?) ?? '',
      approvalNumber: (row['approval_number'] as String?) ?? '',
      logoPath: (row['logo_path'] as String?) ?? '',
    );
  }

  Future<void> saveEstablishment(EstablishmentData data) async {
    BusinessWriteGuard.ensureAllowed('saveEstablishment');
    if (data.name.trim().isEmpty) throw ArgumentError('Le nom de l’établissement est obligatoire.');
    final rows = await _database.db.query('establishments', columns: ['id'], limit: 1);
    final now = DateTime.now().toIso8601String();
    final identityValues = <String, Object?>{
      'name': data.name.trim(),
      'phone': data.phone.trim(),
      'email': data.email.trim(),
      'address': data.address.trim(),
      'approval_number': data.approvalNumber.trim(),
      'logo_path': data.logoPath.trim().isEmpty ? null : data.logoPath.trim(),
      'currency': 'XAF',
      'updated_at': now,
    };
    await _database.db.transaction((txn) async {
      late String establishmentId;
      if (rows.isEmpty) {
        if (!data.schoolYearEnd.isAfter(data.schoolYearStart)) throw ArgumentError('Les dates de l’année scolaire initiale sont invalides.');
        establishmentId = _uuid.v4();
        final existingActiveYears = await txn.query('school_years', where: 'is_active = 1', limit: 1);
        final schoolYearLabel = existingActiveYears.isNotEmpty
            ? '${existingActiveYears.first['label']}'
            : (data.schoolYearLabel.trim().isEmpty
                ? '${data.schoolYearStart.year}-${data.schoolYearEnd.year}'
                : data.schoolYearLabel.trim());
        final schoolYearStart = existingActiveYears.isNotEmpty
            ? '${existingActiveYears.first['start_date']}'
            : data.schoolYearStart.toIso8601String();
        final schoolYearEnd = existingActiveYears.isNotEmpty
            ? '${existingActiveYears.first['end_date']}'
            : data.schoolYearEnd.toIso8601String();
        await txn.insert('establishments', {
          ...identityValues,
          'id': establishmentId,
          'school_year_label': schoolYearLabel,
          'school_year_start': schoolYearStart,
          'school_year_end': schoolYearEnd,
          'created_at': now,
        });
        // Réutiliser une année déjà active si elle existe. Sinon la première
        // configuration crée immédiatement une année scolaire exploitable.
        if (existingActiveYears.isEmpty) {
          await txn.insert('school_years', {
            'id': _uuid.v4(),
            'label': schoolYearLabel,
            'start_date': schoolYearStart,
            'end_date': schoolYearEnd,
            'is_active': 1,
            'created_at': now,
            'updated_at': now,
          });
        }
      } else {
        establishmentId = rows.first['id'] as String;
        await txn.update('establishments', identityValues, where: 'id = ?', whereArgs: [establishmentId]);
      }
      await _audit(txn, 'establishment', establishmentId, rows.isEmpty ? 'create' : 'update', data.name.trim());
    });
  }

  Future<Map<String, int>> notificationThresholds() async {
    const defaults = <String, int>{
      'alert.overdue.high_days': 30,
      'alert.overdue.critical_days': 90,
      'alert.due_soon_days': 3,
      'alert.capacity_percent': 90,
      'alert.backup_stale_days': 7,
    };
    final rows = await _database.db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: "key IN (?,?,?,?,?)",
      whereArgs: defaults.keys.toList(),
    );
    final values = Map<String, int>.from(defaults);
    for (final row in rows) {
      final key = row['key'] as String;
      values[key] = int.tryParse('${row['value']}') ?? defaults[key]!;
    }
    return values;
  }

  Future<void> saveNotificationThresholds({
    required int overdueHighDays,
    required int overdueCriticalDays,
    required int dueSoonDays,
    required int capacityPercent,
    required int backupStaleDays,
  }) async {
    BusinessWriteGuard.ensureAllowed('saveNotificationThresholds');
    if (overdueHighDays < 1 || overdueHighDays > 180) {
      throw ArgumentError('Le seuil élevé doit être compris entre 1 et 180 jours.');
    }
    if (overdueCriticalDays <= overdueHighDays || overdueCriticalDays > 365) {
      throw ArgumentError('Le seuil critique doit être supérieur au seuil élevé et inférieur ou égal à 365 jours.');
    }
    if (dueSoonDays < 1 || dueSoonDays > 30) {
      throw ArgumentError('Le délai avant échéance doit être compris entre 1 et 30 jours.');
    }
    if (capacityPercent < 50 || capacityPercent > 100) {
      throw ArgumentError('Le seuil de capacité doit être compris entre 50 et 100 %.');
    }
    if (backupStaleDays < 1 || backupStaleDays > 30) {
      throw ArgumentError('Le seuil de sauvegarde doit être compris entre 1 et 30 jours.');
    }
    final now = DateTime.now().toIso8601String();
    final values = <String, int>{
      'alert.overdue.high_days': overdueHighDays,
      'alert.overdue.critical_days': overdueCriticalDays,
      'alert.due_soon_days': dueSoonDays,
      'alert.capacity_percent': capacityPercent,
      'alert.backup_stale_days': backupStaleDays,
    };
    await _database.db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.rawInsert(
          'INSERT OR REPLACE INTO app_settings(key,value,updated_at) VALUES(?,?,?)',
          [entry.key, '${entry.value}', now],
        );
      }
      await _audit(
        txn,
        'app_settings',
        'notification_thresholds',
        'update',
        'high=$overdueHighDays/critical=$overdueCriticalDays/due=$dueSoonDays/capacity=$capacityPercent/backup=$backupStaleDays',
      );
    });
  }

  Future<List<SchoolYearItem>> schoolYears() async {
    final rows = await _database.db.query('school_years', orderBy: 'start_date DESC');
    return rows.map((row) => SchoolYearItem(
      id: row['id'] as String,
      label: row['label'] as String,
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: DateTime.parse(row['end_date'] as String),
      isActive: (row['is_active'] as int) == 1,
    )).toList();
  }

  Future<SchoolYearItem?> activeSchoolYear() async {
    final rows = await _database.db.query('school_years', where: 'is_active = 1', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SchoolYearItem(
      id: row['id'] as String,
      label: row['label'] as String,
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: DateTime.parse(row['end_date'] as String),
      isActive: true,
    );
  }

  Future<String> createSchoolYear({
    required String label, required DateTime startDate, required DateTime endDate, bool activate = false}) async {
      BusinessWriteGuard.ensureAllowed('createSchoolYear');
      
    final trimmed = label.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le libellé est obligatoire.');
    if (!endDate.isAfter(startDate)) throw ArgumentError('La date de fin doit être postérieure à la date de début.');
    final duplicate = firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM school_years WHERE lower(label)=lower(?)', [trimmed])) ?? 0;
    if (duplicate > 0) throw StateError('Cette année scolaire existe déjà.');
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      if (activate) await txn.update('school_years', {'is_active': 0, 'updated_at': now}, where: 'is_active = 1');
      await txn.insert('school_years', {
        'id': id, 'label': trimmed, 'start_date': startDate.toIso8601String(), 'end_date': endDate.toIso8601String(),
        'is_active': activate ? 1 : 0, 'created_at': now, 'updated_at': now,
      });
      await _audit(txn, 'school_year', id, 'create', '$trimmed/${activate ? 'active' : 'inactive'}');
    });
    if (activate) await activateSchoolYear(id);
    return id;
  }

  Future<void> activateSchoolYear(String id) async {
    BusinessWriteGuard.ensureAllowed('activateSchoolYear');
    final yearRows = await _database.db.query('school_years', where: 'id = ?', whereArgs: [id], limit: 1);
    if (yearRows.isEmpty) throw StateError('Année scolaire introuvable.');
    final year = yearRows.first;
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      await txn.update('school_years', {'is_active': 0, 'updated_at': now}, where: 'is_active = 1');
      await txn.update('school_years', {'is_active': 1, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
      await txn.update('establishments', {
        'school_year_label': year['label'],
        'school_year_start': year['start_date'],
        'school_year_end': year['end_date'],
        'updated_at': now,
      });
      await _audit(txn, 'school_year', id, 'activate', '${year['label']}');
    });
  }

  Future<void> addClassroom({
    required String cycleId, required String name, int? capacity}) async {
      BusinessWriteGuard.ensureAllowed('addClassroom');
      
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom de la classe est obligatoire.');
    if (capacity != null && capacity <= 0) throw ArgumentError('La capacité doit être supérieure à zéro.');
    final duplicate = firstIntValue(await _database.db.rawQuery(
          'SELECT COUNT(*) FROM classrooms WHERE cycle_id = ? AND lower(name) = lower(?) AND active = 1',
          [cycleId, trimmed],
        )) ?? 0;
    if (duplicate > 0) throw StateError('Une classe active porte déjà ce nom dans ce cycle.');

    final id = _uuid.v4();
    await _database.db.transaction((txn) async {
      await txn.insert('classrooms', {'id': id, 'cycle_id': cycleId, 'name': trimmed, 'capacity': capacity, 'active': 1});
      await _audit(txn, 'classroom', id, 'create', '$cycleId/$trimmed/${capacity ?? ''}');
    });
  }


  Future<String> addCycle({
    required String name, int? sortOrder}) async {
      BusinessWriteGuard.ensureAllowed('addCycle');
      
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom du cycle est obligatoire.');
    final duplicate = firstIntValue(await _database.db.rawQuery(
      'SELECT COUNT(*) FROM cycles WHERE lower(name)=lower(?) AND active=1', [trimmed])) ?? 0;
    if (duplicate > 0) throw StateError('Un cycle actif porte déjà ce nom.');
    final id = _uuid.v4();
    final order = sortOrder ?? ((firstIntValue(await _database.db.rawQuery('SELECT COALESCE(MAX(sort_order),0)+1 FROM cycles')) ?? 1));
    await _database.db.transaction((txn) async {
      await txn.insert('cycles', {'id': id, 'name': trimmed, 'sort_order': order, 'active': 1});
      await _audit(txn, 'cycle', id, 'create', trimmed);
    });
    return id;
  }

  Future<void> updateClassroom({
    required String id, required String name, int? capacity, bool active = true}) async {
      BusinessWriteGuard.ensureAllowed('updateClassroom');
      
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom de la classe est obligatoire.');
    if (capacity != null && capacity <= 0) throw ArgumentError('La capacité doit être supérieure à zéro.');
    final row = await _database.db.query('classrooms', where: 'id=?', whereArgs: [id], limit: 1);
    if (row.isEmpty) throw StateError('Classe introuvable.');
    final cycleId = row.first['cycle_id'] as String;
    final duplicate = firstIntValue(await _database.db.rawQuery(
      'SELECT COUNT(*) FROM classrooms WHERE cycle_id=? AND lower(name)=lower(?) AND id<>? AND active=1', [cycleId, trimmed, id])) ?? 0;
    if (duplicate > 0) throw StateError('Une autre classe active porte déjà ce nom dans ce cycle.');
    await _database.db.transaction((txn) async {
      await txn.update('classrooms', {'name': trimmed, 'capacity': capacity, 'active': active ? 1 : 0}, where: 'id=?', whereArgs: [id]);
      await _audit(txn, 'classroom', id, 'update', '$trimmed/${capacity ?? ''}/${active ? 'active' : 'inactive'}');
    });
  }


  Future<List<DocumentRequirementSetting>> documentRequirements({bool includeInactive = true}) async {
    final rows = await _database.db.query('document_requirements', where: includeInactive ? null : 'active=1', orderBy: 'sort_order, name COLLATE NOCASE');
    return rows.map((r) => DocumentRequirementSetting(
      id:r['id'] as String, name:r['name'] as String, description:r['description'] as String?,
      required:(r['required'] as int? ?? 0)==1, active:(r['active'] as int? ?? 0)==1, sortOrder:r['sort_order'] as int? ?? 0,
    )).toList();
  }

  Future<void> saveDocumentRequirement({
    String? id, required String name, String? description, bool required=true, bool active=true, int sortOrder=0}) async {
      BusinessWriteGuard.ensureAllowed('saveDocumentRequirement');
      
    final trimmed=name.trim(); if(trimmed.isEmpty) throw ArgumentError('Le nom de la pièce est obligatoire.');
    final duplicate=firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM document_requirements WHERE lower(name)=lower(?) AND (? IS NULL OR id<>?)',[trimmed,id,id])) ?? 0;
    if(duplicate>0) throw StateError('Une pièce porte déjà ce nom.');
    final now=DateTime.now().toIso8601String(); final itemId=id??_uuid.v4();
    await _database.db.transaction((txn) async {
      final values={'name':trimmed,'description':description?.trim(),'required':required?1:0,'active':active?1:0,'sort_order':sortOrder,'updated_at':now};
      if(id==null) await txn.insert('document_requirements',{'id':itemId,...values,'created_at':now}); else await txn.update('document_requirements',values,where:'id=?',whereArgs:[id]);
      await _audit(txn,'document_requirement',itemId,id==null?'create':'update','$trimmed/${required?'required':'optional'}/${active?'active':'inactive'}');
    });
  }

  Future<void> updateCycle({
    required String id, required String name, required int sortOrder, required bool active}) async {
      BusinessWriteGuard.ensureAllowed('updateCycle');
      
    final trimmed=name.trim(); if(trimmed.isEmpty) throw ArgumentError('Le nom du cycle est obligatoire.');
    final row=await _database.db.query('cycles',where:'id=?',whereArgs:[id],limit:1); if(row.isEmpty) throw StateError('Cycle introuvable.');
    if(!active){
      final inUse=firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM classrooms WHERE cycle_id=? AND active=1',[id])) ?? 0;
      if(inUse>0) throw StateError('Désactivez d’abord les classes actives de ce cycle.');
    }
    final duplicate=firstIntValue(await _database.db.rawQuery('SELECT COUNT(*) FROM cycles WHERE lower(name)=lower(?) AND id<>? AND active=1',[trimmed,id])) ?? 0;
    if(duplicate>0) throw StateError('Un autre cycle actif porte déjà ce nom.');
    await _database.db.transaction((txn) async { await txn.update('cycles',{'name':trimmed,'sort_order':sortOrder,'active':active?1:0},where:'id=?',whereArgs:[id]); await _audit(txn,'cycle',id,'update','$trimmed/$sortOrder/${active?'active':'inactive'}'); });
  }

  Future<List<PaymentMethodSetting>> paymentMethods({bool includeInactive = true}) async {
    final rows = await _database.db.query(
      'payment_methods',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'active DESC, name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => PaymentMethodSetting(
            id: row['id'] as String,
            name: row['name'] as String,
            requiresReference: (row['requires_reference'] as int? ?? 0) == 1,
            accountType: (row['account_type'] as String? ?? 'cash'),
            active: (row['active'] as int? ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<void> savePaymentMethod({
    String? id,
    required String name,
    required String accountType,
    required bool requiresReference,
    bool active = true,
  }) async {
    BusinessWriteGuard.ensureAllowed('savePaymentMethod');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom du moyen de paiement est obligatoire.');
    const allowedTypes = {'cash', 'mobile', 'bank'};
    if (!allowedTypes.contains(accountType)) {
      throw ArgumentError('Type de compte invalide.');
    }
    final duplicate = firstIntValue(
          await _database.db.rawQuery(
            'SELECT COUNT(*) FROM payment_methods WHERE lower(name)=lower(?) AND (? IS NULL OR id<>?)',
            [trimmed, id, id],
          ),
        ) ??
        0;
    if (duplicate > 0) throw StateError('Un autre moyen de paiement porte déjà ce nom.');

    final methodId = id ?? _uuid.v4();
    await _database.db.transaction((txn) async {
      final values = <String, Object?>{
        'name': trimmed,
        'account_type': accountType,
        'requires_reference': requiresReference ? 1 : 0,
        'active': active ? 1 : 0,
      };
      if (id == null) {
        await txn.insert('payment_methods', {'id': methodId, ...values});
      } else {
        await txn.update('payment_methods', values, where: 'id=?', whereArgs: [id]);
      }
      await _audit(txn, 'payment_method', methodId, id == null ? 'create' : 'update', '$trimmed/$accountType/${requiresReference ? 'reference' : 'no-reference'}/${active ? 'active' : 'inactive'}');
    });
  }

  Future<void> setPaymentMethodActive(String id, bool active) async {
    BusinessWriteGuard.ensureAllowed('setPaymentMethodActive');
    final row = await _database.db.query('payment_methods', where: 'id=?', whereArgs: [id], limit: 1);
    if (row.isEmpty) throw StateError('Moyen de paiement introuvable.');
    await _database.db.transaction((txn) async {
      await txn.update('payment_methods', {'active': active ? 1 : 0}, where: 'id=?', whereArgs: [id]);
      await _audit(txn, 'payment_method', id, active ? 'activate' : 'deactivate', '${row.first['name']}');
    });
  }

  Future<List<CashAccountSetting>> cashAccounts({bool includeInactive = true}) async {
    final rows = await _database.db.query(
      'cash_accounts',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'active DESC, type, name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => CashAccountSetting(
            id: row['id'] as String,
            name: row['name'] as String,
            type: row['type'] as String,
            openingBalance: row['opening_balance'] as int? ?? 0,
            active: (row['active'] as int? ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<void> saveCashAccount({
    String? id,
    required String name,
    required String type,
    required int openingBalance,
    bool active = true,
  }) async {
    BusinessWriteGuard.ensureAllowed('saveCashAccount');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Le nom de la caisse / du compte est obligatoire.');
    if (openingBalance < 0) throw ArgumentError('Le solde initial ne peut pas être négatif.');
    const allowedTypes = {'cash', 'mobile', 'bank'};
    if (!allowedTypes.contains(type)) throw ArgumentError('Type de compte invalide.');
    final duplicate = firstIntValue(
          await _database.db.rawQuery(
            'SELECT COUNT(*) FROM cash_accounts WHERE lower(name)=lower(?) AND (? IS NULL OR id<>?)',
            [trimmed, id, id],
          ),
        ) ??
        0;
    if (duplicate > 0) throw StateError('Une autre caisse / un autre compte porte déjà ce nom.');
    final accountId = id ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await _database.db.transaction((txn) async {
      if (id != null) {
        final existing = await txn.query('cash_accounts', where: 'id=?', whereArgs: [id], limit: 1);
        if (existing.isEmpty) throw StateError('Caisse / compte introuvable.');
        final oldType = existing.first['type'] as String;
        final oldOpeningBalance = existing.first['opening_balance'] as int? ?? 0;
        final movements = firstIntValue(await txn.rawQuery(
              '''SELECT
                   (SELECT COUNT(*) FROM payments WHERE cash_account_id=?) +
                   (SELECT COUNT(*) FROM expenses WHERE cash_account_id=?) +
                   (SELECT COUNT(*) FROM cash_transfers WHERE from_account_id=? OR to_account_id=?) +
                   (SELECT COUNT(*) FROM cash_sessions WHERE cash_account_id=?)''',
              [id, id, id, id, id],
            )) ??
            0;
        if (movements > 0 && oldType != type) {
          throw StateError('Le type d’un compte déjà utilisé ne peut pas être modifié. Créez un nouveau compte.');
        }
        if (movements > 0 && oldOpeningBalance != openingBalance) {
          throw StateError('Le solde initial d’un compte déjà utilisé ne peut pas être modifié. Utilisez un transfert ou une écriture de régularisation.');
        }
      }
      final values = <String, Object?>{
        'name': trimmed,
        'type': type,
        'opening_balance': openingBalance,
        'active': active ? 1 : 0,
      };
      if (id == null) {
        await txn.insert('cash_accounts', {'id': accountId, ...values, 'created_at': now});
      } else {
        await txn.update('cash_accounts', values, where: 'id=?', whereArgs: [id]);
      }
      await _audit(txn, 'cash_account', accountId, id == null ? 'create' : 'update', '$trimmed/$type/$openingBalance/${active ? 'active' : 'inactive'}');
    });
  }

  Future<void> setCashAccountActive(String id, bool active) async {
    BusinessWriteGuard.ensureAllowed('setCashAccountActive');
    final row = await _database.db.query('cash_accounts', where: 'id=?', whereArgs: [id], limit: 1);
    if (row.isEmpty) throw StateError('Caisse / compte introuvable.');
    if (!active) {
      final openSessions = firstIntValue(await _database.db.rawQuery(
            "SELECT COUNT(*) FROM cash_sessions WHERE cash_account_id=? AND status='open'",
            [id],
          )) ??
          0;
      if (openSessions > 0) throw StateError('Clôturez la caisse avant de la désactiver.');
    }
    await _database.db.transaction((txn) async {
      await txn.update('cash_accounts', {'active': active ? 1 : 0}, where: 'id=?', whereArgs: [id]);
      await _audit(txn, 'cash_account', id, active ? 'activate' : 'deactivate', '${row.first['name']}');
    });
  }

  Future<List<Map<String, Object?>>> cycles({bool includeInactive = false}) => _database.db.query('cycles', where: includeInactive ? null : 'active = 1', orderBy: 'sort_order, name COLLATE NOCASE');

  Future<void> _audit(DatabaseExecutor db, String entityType, String entityId, String action, String newValue) => db.insert('audit_log', {
    'entity_type': entityType,
    'entity_id': entityId,
    'action': action,
    'new_value': newValue,
    'operator_name': OperatorSession.current,
    'operator_id': OperatorSession.userId,
    'operator_role': OperatorSession.role,
    'created_at': DateTime.now().toIso8601String(),
  });
}
