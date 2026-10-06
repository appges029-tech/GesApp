import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/db/app_database.dart';
import '../../core/session/operator_session.dart';

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

  factory TenantMembershipCache.fromMap(
    Map<String, Object?> row, {
    String? backupSecret,
  }) =>
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
        backupSecret: backupSecret ?? row['backup_secret'] as String?,
      );
}

class TenantRepository {
  TenantRepository(this._database);
  final AppDatabase _database;

  static const _secure = FlutterSecureStorage();
  static const _secretPrefix = 'gesapp.cloud.backup_secret.';
  Future<void> ensureOrganizationBinding(String organizationId) async {
    final rows = await _database.db.query(
      'cloud_tenant_cache',
      columns: ['organization_id'],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final bound = rows.first['organization_id']?.toString();
    if (bound != null && bound.isNotEmpty && bound != organizationId) {
      throw StateError(
        'Cette installation GesApp est déjà liée à un autre établissement. '
        'La séparation des données empêche de mélanger deux écoles sur la même base locale.',
      );
    }
  }

  Future<TenantMembershipCache?> cachedMembership() async {
    final rows = await _database.db.query(
      'cloud_tenant_cache',
      where: 'active=1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = Map<String, Object?>.from(rows.first);
    final orgId = row['organization_id'] as String;
    String? secret;
    try {
      secret = await _secure.read(key: '$_secretPrefix$orgId');
      final legacy = row['backup_secret'] as String?;
      if ((secret == null || secret.isEmpty) && legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: '$_secretPrefix$orgId', value: legacy);
        secret = legacy;
        await _database.db.update(
          'cloud_tenant_cache',
          {'backup_secret': null},
          where: 'organization_id = ?',
          whereArgs: [orgId],
        );
      }
    } catch (_) {
      secret = row['backup_secret'] as String?;
    }
    return TenantMembershipCache.fromMap(row, backupSecret: secret);
  }

  Future<void> cacheMembership(TenantMembershipCache membership) async {
    await ensureOrganizationBinding(membership.organizationId);

    String? databaseFallbackSecret;
    if (membership.backupSecret != null && membership.backupSecret!.isNotEmpty) {
      try {
        await _secure.write(
          key: '$_secretPrefix${membership.organizationId}',
          value: membership.backupSecret,
        );
      } catch (_) {
        databaseFallbackSecret = membership.backupSecret;
      }
    }

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
        'backup_secret': databaseFallbackSecret,
        'updated_at': membership.updatedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> clearMembership({bool clearSecret = false}) async {
    final rows = await _database.db.query(
      'cloud_tenant_cache',
      limit: 1,
    );
    final orgId =
        rows.isEmpty ? null : rows.first['organization_id']?.toString();

    await _database.db.update(
      'cloud_tenant_cache',
      {
        'active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
    );

    if (clearSecret && orgId != null && orgId.isNotEmpty) {
      try {
        await _secure.delete(key: '$_secretPrefix$orgId');
      } catch (_) {}
    }
    OperatorSession.clear();
  }

  Future<void> applyOrganizationIdentity({
    required String organizationId,
    required String organizationName,
  }) async {
    final name = organizationName.trim();
    if (name.isEmpty) return;
    await ensureOrganizationBinding(organizationId);

    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final startYear = now.month >= 7 ? now.year : now.year - 1;
    final start = DateTime(startYear, 9, 1);
    final end = DateTime(startYear + 1, 6, 30, 23, 59, 59);
    final yearId = 'tenant-$organizationId-$startYear';

    await _database.db.transaction((txn) async {
      final syncRows = await txn.query(
        'cloud_sync_state',
        columns: ['local_revision'],
        where: "id='main'",
        limit: 1,
      );
      final revisionBefore = syncRows.isEmpty
          ? 0
          : (syncRows.first['local_revision'] as int? ?? 0);

      final rows = await txn.query('establishments', limit: 1);
      if (rows.isNotEmpty) {
        final currentName = rows.first['name']?.toString().trim() ?? '';
        if (currentName != name) {
          await txn.update(
            'establishments',
            {'name': name, 'updated_at': nowIso},
            where: 'id = ?',
            whereArgs: [rows.first['id']],
          );
        }
      } else {
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
        final activeYear = await txn.query(
          'school_years',
          where: 'is_active = 1',
          limit: 1,
        );
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
      }

      await txn.update(
        'cloud_sync_state',
        {
          'local_revision': revisionBefore,
          'updated_at': nowIso,
        },
        where: "id='main'",
      );
    });
  }

  Future<Map<String, Object?>> syncState() async {
    final rows = await _database.db.query(
      'cloud_sync_state',
      where: "id='main'",
      limit: 1,
    );
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
      return (await _database.db.query(
        'cloud_sync_state',
        where: "id='main'",
        limit: 1,
      ))
          .first;
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
    final values = <String, Object?>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (localRevision != null) values['local_revision'] = localRevision;
    if (lastUploadedLocalRevision != null) {
      values['last_uploaded_local_revision'] = lastUploadedLocalRevision;
    }
    if (knownRemoteRevision != null) {
      values['known_remote_revision'] = knownRemoteRevision;
    }
    if (status != null) values['status'] = status;
    values['last_error'] = lastError;
    if (lastSyncedAt != null) {
      values['last_synced_at'] = lastSyncedAt.toIso8601String();
    }
    await _database.db.update(
      'cloud_sync_state',
      values,
      where: "id='main'",
    );
  }

  Future<int> localRevision() async {
    final row = await syncState();
    return (row['local_revision'] as int?) ?? 0;
  }
}
