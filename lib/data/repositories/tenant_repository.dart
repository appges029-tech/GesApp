import 'package:sqflite_common/sqlite_api.dart';

import '../../core/db/app_database.dart';
import '../../core/session/operator_session.dart';
import '../../core/session/tenant_data_isolation.dart';

class TenantMembershipCache {
  const TenantMembershipCache({
    required this.organizationId,
    required this.organizationCode,
    required this.organizationName,
    required this.cloudUserId,
    required this.displayName,
    required this.role,
    required this.username,
    required this.active,
    required this.mustChangePassword,
    required this.updatedAt,
    this.backupSecret,
  });

  final String organizationId;
  final String organizationCode;
  final String organizationName;
  final String cloudUserId;
  final String displayName;
  final String role;
  final String? username;
  final bool active;
  final bool mustChangePassword;
  final DateTime updatedAt;
  final String? backupSecret;

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';

  factory TenantMembershipCache.fromMap(Map<String, Object?> row) =>
      TenantMembershipCache(
        organizationId: row['organization_id'] as String,
        organizationCode: row['organization_code'] as String,
        organizationName: row['organization_name'] as String,
        cloudUserId: row['cloud_user_id'] as String,
        displayName: row['display_name'] as String,
        role: row['role'] as String,
        username: row['username'] as String?,
        active: (row['active'] as int? ?? 0) == 1,
        mustChangePassword: (row['must_change_password'] as int? ?? 0) == 1,
        updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
        backupSecret: row['backup_secret'] as String?,
      );
}

class TenantRepository {
  TenantRepository(this._database);
  final AppDatabase _database;


  /// Verrouille définitivement cette base SQLite sur l'école d'origine.
  ///
  /// Un seul fichier gesapp.db existe par installation : sans cette protection,
  /// un changement d'école réétiquette et sauvegarde les données de l'autre.
  /// Les utilisateurs qui gèrent plusieurs écoles doivent utiliser des bases
  /// isolées (autres profils / installations) jusqu'à une vraie partition.
  Future<void> ensureOrganizationIsolated(String organizationId) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}
    final rows = await _database.db.query(
      'cloud_tenant_cache',
      where: 'active=1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TenantMembershipCache.fromMap(rows.first);
  }

  Future<void> cacheMembership(TenantMembershipCache membership) async {
    await _database.db.transaction((txn) async {
      await txn.delete('cloud_tenant_cache');
      await txn.insert('cloud_tenant_cache', {
        'organization_id': membership.organizationId,
        'organization_code': membership.organizationCode,
        'organization_name': membership.organizationName,
        'cloud_user_id': membership.cloudUserId,
        'display_name': membership.displayName,
        'role': membership.role,
        'username': membership.username,
        'active': membership.active ? 1 : 0,
        'must_change_password': membership.mustChangePassword ? 1 : 0,
        'backup_secret': membership.backupSecret,
        'updated_at': membership.updatedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('audit_log', {
        'entity_type': 'tenant_session',
        'entity_id': membership.organizationId,
        'action': 'cache_membership',
        'new_value': '${membership.organizationCode}/${membership.role}/${membership.cloudUserId}',
        'operator_name': membership.displayName,
        'operator_id': membership.cloudUserId,
        'operator_role': membership.role,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> clearMembership() async {
    await _database.db.delete('cloud_tenant_cache');
    OperatorSession.clear();
  }

  /// Aligne l'identité locale affichée par GesApp sur le tenant Supabase.
  /// Il s'agit d'une opération système de bootstrap, pas d'une écriture métier
  /// réalisée par l'administrateur.
  Future<void> applyOrganizationIdentity({
    required String organizationId,
    required String organizationName,
  }) async {
    final name = organizationName.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final rows = await _database.db.query('establishments', limit: 1);
    if (rows.isNotEmpty) {
      await _database.db.update(
        'establishments',
        {'name': name, 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
      return;
    }

    // Première installation : l'ancien assistant local n'est plus affiché.
    // On crée donc un socle scolaire minimal que le gestionnaire pourra
    // compléter ensuite dans Réglages.
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    final start = DateTime(startYear, 9, 1);
    final end = DateTime(startYear + 1, 6, 30, 23, 59, 59);
    final yearId = 'tenant-$organizationId-$startYear';
    await _database.db.transaction((txn) async {
      await txn.insert('establishments', {
        'id': organizationId,
        'name': name,
        'logo_path': null,
        'phone': null,
        'email': null,
        'address': null,
        'approval_number': null,
        'currency': 'XAF',
        'school_year_label': '$startYear-${startYear + 1}',
        'school_year_start': start.toIso8601String(),
        'school_year_end': end.toIso8601String(),
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      final activeYear = await txn.query('school_years', where: 'is_active = 1', limit: 1);
      if (activeYear.isEmpty) {
        await txn.insert('school_years', {
          'id': yearId,
          'label': '$startYear-${startYear + 1}',
          'start_date': start.toIso8601String(),
          'end_date': end.toIso8601String(),
          'is_active': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      }
    });
  }

  Future<Map<String, Object?>> syncState() async {
    final rows = await _database.db.query('cloud_sync_state', where: "id='main'", limit: 1);
    if (rows.isEmpty) {
      final now = DateTime.now().toIso8601String();
      await _database.db.insert('cloud_sync_state', {
        'id': 'main',
        'local_revision': 0,
        'last_uploaded_local_revision': 0,
        'known_remote_revision': 0,
        'status': 'idle',
        'last_error': null,
        'last_synced_at': null,
        'updated_at': now,
      });
      return (await _database.db.query('cloud_sync_state', where: "id='main'", limit: 1)).first;
    }
    return rows.first;
  }

  Future<void> updateSyncState({
    int? localRevision,
    int? lastUploadedLocalRevision,
    int? knownRemoteRevision,
    String? status,
    String? lastError,
    DateTime? lastSyncedAt,
  }) async {
    final values = <String, Object?>{'updated_at': DateTime.now().toIso8601String()};
    if (localRevision != null) values['local_revision'] = localRevision;
    if (lastUploadedLocalRevision != null) values['last_uploaded_local_revision'] = lastUploadedLocalRevision;
    if (knownRemoteRevision != null) values['known_remote_revision'] = knownRemoteRevision;
    if (status != null) values['status'] = status;
    values['last_error'] = lastError;
    if (lastSyncedAt != null) values['last_synced_at'] = lastSyncedAt.toIso8601String();
    await _database.db.update('cloud_sync_state', values, where: "id='main'");
  }

  Future<int> localRevision() async {
    final row = await syncState();
    return (row['local_revision'] as int?) ?? 0;
  }
}
).hasMatch(organizationId)) {
      throw StateError('Identifiant établissement invalide.');
    }
    const key = 'gesapp.cloud.bound_organization_id.v1';
    await _database.db.transaction((txn) async {
      final binding = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      final stored = binding.isEmpty ? null : binding.first['value']?.toString();
      TenantDataIsolation.requireSameTenant(organizationId, stored);

      final established = await txn.query('establishments', columns: ['id']);
      if (established.any((row) => row['id']?.toString() != organizationId)) {
        throw StateError(
          'Sécurité : la base contient l’identité d’un autre établissement. '
          'Aucune donnée ne sera copiée ni réétiquetée.',
        );
      }
      final cached = await txn.query('cloud_tenant_cache', columns: ['organization_id']);
      if (cached.any((row) => row['organization_id']?.toString() != organizationId)) {
        throw StateError('Sécurité : les données locales appartiennent à un autre établissement.');
      }

      if (stored == null && established.isEmpty && cached.isEmpty) {
        for (final table in const ['students', 'payments', 'dues', 'expenses', 'families']) {
          final countRows = await txn.rawQuery('SELECT COUNT(*) AS n FROM $table');
          final count = (countRows.first['n'] as num?)?.toInt() ?? 0;
          if (count > 0) {
            throw StateError(
              'Une ancienne base scolaire non attribuée contient des données. '
              'Sauvegardez-la et effectuez une migration contrôlée avant de '
              'la rattacher à un établissement.',
            );
          }
        }
      }
      if (stored == null) {
        await txn.insert('app_settings', {
          'key': key,
          'value': organizationId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  Future<TenantMembershipCache?> cachedMembership() async {
    final rows = await _database.db.query(
      'cloud_tenant_cache',
      where: 'active=1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TenantMembershipCache.fromMap(rows.first);
  }

  Future<void> cacheMembership(TenantMembershipCache membership) async {
    await _database.db.transaction((txn) async {
      await txn.delete('cloud_tenant_cache');
      await txn.insert('cloud_tenant_cache', {
        'organization_id': membership.organizationId,
        'organization_code': membership.organizationCode,
        'organization_name': membership.organizationName,
        'cloud_user_id': membership.cloudUserId,
        'display_name': membership.displayName,
        'role': membership.role,
        'username': membership.username,
        'active': membership.active ? 1 : 0,
        'must_change_password': membership.mustChangePassword ? 1 : 0,
        'backup_secret': membership.backupSecret,
        'updated_at': membership.updatedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('audit_log', {
        'entity_type': 'tenant_session',
        'entity_id': membership.organizationId,
        'action': 'cache_membership',
        'new_value': '${membership.organizationCode}/${membership.role}/${membership.cloudUserId}',
        'operator_name': membership.displayName,
        'operator_id': membership.cloudUserId,
        'operator_role': membership.role,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> clearMembership() async {
    await _database.db.delete('cloud_tenant_cache');
    OperatorSession.clear();
  }

  /// Aligne l'identité locale affichée par GesApp sur le tenant Supabase.
  /// Il s'agit d'une opération système de bootstrap, pas d'une écriture métier
  /// réalisée par l'administrateur.
  Future<void> applyOrganizationIdentity({
    required String organizationId,
    required String organizationName,
  }) async {
    final name = organizationName.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final rows = await _database.db.query('establishments', limit: 1);
    if (rows.isNotEmpty) {
      await _database.db.update(
        'establishments',
        {'name': name, 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
      return;
    }

    // Première installation : l'ancien assistant local n'est plus affiché.
    // On crée donc un socle scolaire minimal que le gestionnaire pourra
    // compléter ensuite dans Réglages.
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    final start = DateTime(startYear, 9, 1);
    final end = DateTime(startYear + 1, 6, 30, 23, 59, 59);
    final yearId = 'tenant-$organizationId-$startYear';
    await _database.db.transaction((txn) async {
      await txn.insert('establishments', {
        'id': organizationId,
        'name': name,
        'logo_path': null,
        'phone': null,
        'email': null,
        'address': null,
        'approval_number': null,
        'currency': 'XAF',
        'school_year_label': '$startYear-${startYear + 1}',
        'school_year_start': start.toIso8601String(),
        'school_year_end': end.toIso8601String(),
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      final activeYear = await txn.query('school_years', where: 'is_active = 1', limit: 1);
      if (activeYear.isEmpty) {
        await txn.insert('school_years', {
          'id': yearId,
          'label': '$startYear-${startYear + 1}',
          'start_date': start.toIso8601String(),
          'end_date': end.toIso8601String(),
          'is_active': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      }
    });
  }

  Future<Map<String, Object?>> syncState() async {
    final rows = await _database.db.query('cloud_sync_state', where: "id='main'", limit: 1);
    if (rows.isEmpty) {
      final now = DateTime.now().toIso8601String();
      await _database.db.insert('cloud_sync_state', {
        'id': 'main',
        'local_revision': 0,
        'last_uploaded_local_revision': 0,
        'known_remote_revision': 0,
        'status': 'idle',
        'last_error': null,
        'last_synced_at': null,
        'updated_at': now,
      });
      return (await _database.db.query('cloud_sync_state', where: "id='main'", limit: 1)).first;
    }
    return rows.first;
  }

  Future<void> updateSyncState({
    int? localRevision,
    int? lastUploadedLocalRevision,
    int? knownRemoteRevision,
    String? status,
    String? lastError,
    DateTime? lastSyncedAt,
  }) async {
    final values = <String, Object?>{'updated_at': DateTime.now().toIso8601String()};
    if (localRevision != null) values['local_revision'] = localRevision;
    if (lastUploadedLocalRevision != null) values['last_uploaded_local_revision'] = lastUploadedLocalRevision;
    if (knownRemoteRevision != null) values['known_remote_revision'] = knownRemoteRevision;
    if (status != null) values['status'] = status;
    values['last_error'] = lastError;
    if (lastSyncedAt != null) values['last_synced_at'] = lastSyncedAt.toIso8601String();
    await _database.db.update('cloud_sync_state', values, where: "id='main'");
  }

  Future<int> localRevision() async {
    final row = await syncState();
    return (row['local_revision'] as int?) ?? 0;
  }
}
