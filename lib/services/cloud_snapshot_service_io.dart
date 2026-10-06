import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cloud/supabase_bootstrap.dart';
import '../core/db/app_database.dart';
import '../core/session/operator_session.dart';
import '../core/sync/sync_maintenance.dart';
import '../data/repositories/tenant_repository.dart';
import 'json_data_service.dart';

class CloudSyncStatus {
  const CloudSyncStatus({
    required this.state,
    this.message,
    this.lastSyncedAt,
  });

  final String state;
  final String? message;
  final DateTime? lastSyncedAt;
}

class CloudSnapshotService {
  CloudSnapshotService._();
  static final instance = CloudSnapshotService._();

  static const _bucket = 'gesapp-backups';
  static const _magic = 'GESAPPSYNC1';
  static const _nonceLength = 12;

  final _aes = AesGcm.with256bits();
  final _tenant = TenantRepository(AppDatabase.instance);
  final _json = JsonDataService();

  Timer? _timer;
  bool _running = false;
  bool _resyncRequested = false;

  final ValueNotifier<CloudSyncStatus> status = ValueNotifier(
    const CloudSyncStatus(state: 'idle'),
  );

  void start() {
    _timer?.cancel();
    unawaited(synchronize());
    _timer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(synchronize()),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> resolveConflictUsingCloud() async {
    if (_running ||
        !OperatorSession.isAuthenticated ||
        !SupabaseBootstrap.isInitialized) {
      return;
    }
    final orgId = OperatorSession.organizationId;
    if (orgId == null) return;

    _running = true;
    status.value = const CloudSyncStatus(
      state: 'restoring',
      message: 'Archivage local puis restauration de la version cloud…',
    );
    try {
      final membership = await _tenant.cachedMembership();
      final secret = membership?.backupSecret;
      if (membership == null || secret == null || secret.length < 16) {
        throw StateError(
          'Clé de sauvegarde de l’établissement indisponible.',
        );
      }

      final metadata = await _remoteMetadata(orgId);
      final remoteRevision = (metadata?['revision'] as num?)?.toInt() ?? 0;
      final remotePath = metadata?['current_path']?.toString();
      if (remotePath == null || remotePath.isEmpty || remoteRevision <= 0) {
        throw StateError(
          'Aucune version cloud exploitable n’est disponible.',
        );
      }

      // Ne jamais jeter silencieusement la version locale d'un conflit.
      await _archiveLocalConflictSnapshot(
        organizationId: orgId,
        backupSecret: secret,
      );

      await _downloadAndRestore(
        path: remotePath,
        backupSecret: secret,
        remoteRevision: remoteRevision,
        expectedChecksum: metadata?['checksum_sha256']?.toString(),
        organizationId: membership.organizationId,
        organizationName: membership.organizationName,
      );
    } catch (error) {
      final message = _syncErrorMessage(error);
      await _tenant.updateSyncState(status: 'error', lastError: message);
      status.value = CloudSyncStatus(state: 'error', message: message);
    } finally {
      _running = false;
    }
  }

  Future<void> resolveConflictKeepingLocal() async {
    if (!OperatorSession.isManager) {
      status.value = const CloudSyncStatus(
        state: 'error',
        message: 'Seul un gestionnaire peut publier la version locale.',
      );
      return;
    }
    if (_running ||
        !OperatorSession.isAuthenticated ||
        !SupabaseBootstrap.isInitialized) {
      return;
    }
    final orgId = OperatorSession.organizationId;
    if (orgId == null) return;

    _running = true;
    try {
      final metadata = await _remoteMetadata(orgId);
      final remoteRevision = (metadata?['revision'] as num?)?.toInt() ?? 0;
      await _tenant.updateSyncState(
        knownRemoteRevision: remoteRevision,
        status: 'idle',
        lastError: null,
      );
    } catch (error) {
      final message = _syncErrorMessage(error);
      await _tenant.updateSyncState(status: 'error', lastError: message);
      status.value = CloudSyncStatus(state: 'error', message: message);
      return;
    } finally {
      _running = false;
    }

    // L'ancien snapshot cloud n'est plus supprimé après publication : il reste
    // récupérable dans le bucket privé même lorsque la version locale est choisie.
    await synchronize(force: true);
  }

  Future<void> synchronize({bool force = false}) async {
    if (_running ||
        SyncMaintenance.isActive ||
        !OperatorSession.isAuthenticated ||
        !SupabaseBootstrap.isInitialized) {
      return;
    }

    final orgId = OperatorSession.organizationId;
    if (orgId == null) return;

    _running = true;
    _resyncRequested = false;
    status.value = const CloudSyncStatus(
      state: 'syncing',
      message: 'Synchronisation en cours…',
    );

    try {
      final membership = await _tenant.cachedMembership();
      final secret = membership?.backupSecret;
      if (membership == null || secret == null || secret.length < 16) {
        throw StateError(
          'Clé de sauvegarde de l’établissement indisponible.',
        );
      }

      var state = await _tenant.syncState();
      var localRevision = (state['local_revision'] as int?) ?? 0;
      var lastUploaded =
          (state['last_uploaded_local_revision'] as int?) ?? 0;
      final knownRemote = (state['known_remote_revision'] as int?) ?? 0;

      final metadata = await _remoteMetadata(orgId);
      final remoteRevision = (metadata?['revision'] as num?)?.toInt() ?? 0;
      final remotePath = metadata?['current_path']?.toString();
      final remoteChecksum = metadata?['checksum_sha256']?.toString();
      var localDirty = localRevision != lastUploaded;

      final hasRemoteSnapshot =
          remoteRevision > 0 && remotePath != null && remotePath.isNotEmpty;

      // Première connexion d'un nouvel appareil : les tables techniques et les
      // données par défaut locales ne doivent jamais créer un faux conflit.
      // Un poste qui n'a encore jamais connu de révision distante reçoit d'abord
      // la version cloud existante avant d'ouvrir HomeShell.
      final firstCloudContact = hasRemoteSnapshot &&
          knownRemote == 0 &&
          lastUploaded == 0;
      if (firstCloudContact) {
        await _downloadAndRestore(
          path: remotePath,
          backupSecret: secret,
          remoteRevision: remoteRevision,
          expectedChecksum: remoteChecksum,
          organizationId: membership.organizationId,
          organizationName: membership.organizationName,
        );
        return;
      }

      // Une autre machine a publié une version plus récente.
      if (remoteRevision > knownRemote && hasRemoteSnapshot) {
        if (!localDirty) {
          await _downloadAndRestore(
            path: remotePath,
            backupSecret: secret,
            remoteRevision: remoteRevision,
            expectedChecksum: remoteChecksum,
            organizationId: membership.organizationId,
            organizationName: membership.organizationName,
          );
          return;
        }

        await _tenant.updateSyncState(
          status: 'conflict',
          lastError:
              'Une version cloud plus récente existe alors que cet appareil contient aussi des modifications locales.',
        );
        status.value = const CloudSyncStatus(
          state: 'conflict',
          message:
              'Conflit détecté : aucune donnée n’a été écrasée. Les deux versions restent récupérables.',
        );
        return;
      }

      // Administrateur : lecture seule, jamais de publication métier.
      if (OperatorSession.isAdmin) {
        if (hasRemoteSnapshot && remoteRevision > knownRemote) {
          await _downloadAndRestore(
            path: remotePath,
            backupSecret: secret,
            remoteRevision: remoteRevision,
            expectedChecksum: remoteChecksum,
            organizationId: membership.organizationId,
            organizationName: membership.organizationName,
          );
        } else {
          status.value = CloudSyncStatus(
            state: 'up_to_date',
            lastSyncedAt: DateTime.now(),
          );
        }
        return;
      }

      final needsInitialUpload = !hasRemoteSnapshot;
      if (needsInitialUpload) {
        // Pour un nouvel établissement sans snapshot, créer uniquement ici le
        // socle local. L'opération système préserve la révision de synchro.
        await _tenant.applyOrganizationIdentity(
          organizationId: membership.organizationId,
          organizationName: membership.organizationName,
        );
        state = await _tenant.syncState();
        localRevision = (state['local_revision'] as int?) ?? 0;
        lastUploaded =
            (state['last_uploaded_local_revision'] as int?) ?? 0;
        localDirty = localRevision != lastUploaded;
      }

      if (!force && !localDirty && !needsInitialUpload) {
        final now = DateTime.now();
        await _tenant.updateSyncState(
          knownRemoteRevision: remoteRevision,
          status: 'up_to_date',
          lastError: null,
          lastSyncedAt: now,
        );
        status.value =
            CloudSyncStatus(state: 'up_to_date', lastSyncedAt: now);
        return;
      }

      // La révision capturée AVANT l'export est la seule révision que ce
      // snapshot pourra déclarer comme publiée.
      final exportRevision = localRevision;
      final exported = await _json.exportAll(
        await AppDatabase.instance.databasePath,
        trustedSystem: true,
      );

      try {
        // Si une écriture a eu lieu pendant la construction du JSON, ce fichier
        // peut être un mélange de deux instants. On le jette et on recommence
        // plus tard au lieu de publier un snapshot potentiellement incohérent.
        final revisionAfterExport = await _tenant.localRevision();
        if (revisionAfterExport != exportRevision) {
          await _tenant.updateSyncState(
            status: 'pending',
            lastError: null,
          );
          status.value = const CloudSyncStatus(
            state: 'pending',
            message:
                'De nouvelles modifications ont été détectées pendant la préparation. Une nouvelle synchronisation va être lancée.',
          );
          _resyncRequested = true;
          return;
        }

        final rawSnapshot = await exported.file.readAsBytes();
        final compressedSnapshot = gzip.encode(rawSnapshot);
        final encrypted = await _encrypt(compressedSnapshot, secret);

        final nextRemote = remoteRevision + 1;
        final uniqueSuffix =
            '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
        final storagePath =
            '$orgId/snapshot-$nextRemote-$uniqueSuffix.gesync';

        await _retryTransientNetwork(
          () => SupabaseBootstrap.client.storage.from(_bucket).uploadBinary(
                storagePath,
                encrypted,
                fileOptions: const FileOptions(
                  upsert: false,
                  contentType: 'application/octet-stream',
                  cacheControl: '0',
                ),
              ),
        );

        final checksum = sha256.convert(encrypted).toString();
        final now = DateTime.now();
        var metadataCommitted = false;

        try {
          if (metadata == null) {
            await _retryTransientNetwork(
              () => SupabaseBootstrap.client.from('sync_metadata').insert({
                'organization_id': orgId,
                'revision': nextRemote,
                'current_path': storagePath,
                'checksum_sha256': checksum,
                'size_bytes': encrypted.length,
                'uploaded_by': OperatorSession.cloudUserId,
                'uploaded_at': now.toUtc().toIso8601String(),
                'updated_at': now.toUtc().toIso8601String(),
              }),
            );
            metadataCommitted = true;
          } else {
            final updated = await _retryTransientNetwork(
              () => SupabaseBootstrap.client
                  .from('sync_metadata')
                  .update({
                    'revision': nextRemote,
                    'current_path': storagePath,
                    'checksum_sha256': checksum,
                    'size_bytes': encrypted.length,
                    'uploaded_by': OperatorSession.cloudUserId,
                    'uploaded_at': now.toUtc().toIso8601String(),
                    'updated_at': now.toUtc().toIso8601String(),
                  })
                  .eq('organization_id', orgId)
                  .eq('revision', remoteRevision)
                  .select('revision'),
            );
            metadataCommitted = updated.isNotEmpty;
            if (!metadataCommitted) {
              throw StateError(
                'La sauvegarde cloud a changé pendant l’envoi. Nouvelle tentative requise.',
              );
            }
          }
        } finally {
          if (!metadataCommitted) {
            try {
              await _retryTransientNetwork(
                () => SupabaseBootstrap.client.storage
                    .from(_bucket)
                    .remove([storagePath]),
              );
            } catch (_) {
              // Un fichier orphelin n'est jamais référencé par sync_metadata.
            }
          }
        }

        // IMPORTANT : on conserve volontairement l'ancien remotePath.
        // Il constitue une génération de récupération en cas d'erreur logique.
        await _tenant.updateSyncState(
          lastUploadedLocalRevision: exportRevision,
          knownRemoteRevision: nextRemote,
          status: 'up_to_date',
          lastError: null,
          lastSyncedAt: now,
        );

        final currentRevision = await _tenant.localRevision();
        if (currentRevision != exportRevision) {
          await _tenant.updateSyncState(
            status: 'pending',
            lastError: null,
          );
          status.value = CloudSyncStatus(
            state: 'pending',
            message:
                'La version $exportRevision est sauvegardée. Des modifications plus récentes restent à envoyer.',
            lastSyncedAt: now,
          );
          _resyncRequested = true;
        } else {
          status.value =
              CloudSyncStatus(state: 'up_to_date', lastSyncedAt: now);
        }
      } finally {
        if (await exported.file.exists()) {
          await exported.file.delete();
        }
      }
    } catch (error) {
      final message = _syncErrorMessage(error);
      try {
        await _tenant.updateSyncState(
          status: 'error',
          lastError: message,
        );
      } catch (_) {}
      status.value = CloudSyncStatus(state: 'error', message: message);
    } finally {
      _running = false;
    }

    if (_resyncRequested &&
        OperatorSession.isAuthenticated &&
        !SyncMaintenance.isActive) {
      _resyncRequested = false;
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 2),
          () => synchronize(),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _remoteMetadata(String orgId) async {
    final rows = await _retryTransientNetwork(
      () => SupabaseBootstrap.client
          .from('sync_metadata')
          .select(
            'revision,current_path,checksum_sha256,size_bytes,uploaded_at',
          )
          .eq('organization_id', orgId)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<T> _retryTransientNetwork<T>(
    Future<T> Function() action, {
    int attempts = 4,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (!_isTransientNetworkError(error) || attempt == attempts - 1) {
          rethrow;
        }
        final base = 400 * (1 << attempt);
        final jitter = Random.secure().nextInt(250);
        await Future<void>.delayed(
          Duration(milliseconds: base + jitter),
        );
      }
    }
    throw StateError('Échec réseau inattendu : $lastError');
  }

  bool _isTransientNetworkError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('timed out') ||
        raw.contains('timeoutexception') ||
        raw.contains('502') ||
        raw.contains('503') ||
        raw.contains('504') ||
        raw.contains('bad gateway') ||
        raw.contains('service unavailable') ||
        raw.contains('gateway timeout');
  }

  String _syncErrorMessage(Object error) {
    if (_isTransientNetworkError(error)) {
      return 'Connexion Internet temporairement indisponible. '
          'Vos données restent enregistrées sur cet appareil. '
          'GesApp réessaiera automatiquement lorsque la connexion revient.';
    }
    return error.toString();
  }

  Future<void> _archiveLocalConflictSnapshot({
    required String organizationId,
    required String backupSecret,
  }) async {
    final exported = await _json.exportAll(
      await AppDatabase.instance.databasePath,
      trustedSystem: true,
    );
    try {
      final raw = await exported.file.readAsBytes();
      final encrypted = await _encrypt(gzip.encode(raw), backupSecret);
      final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
      final path =
          '$organizationId/recovery/conflict-local-$stamp.gesync';
      await _retryTransientNetwork(
        () => SupabaseBootstrap.client.storage.from(_bucket).uploadBinary(
              path,
              encrypted,
              fileOptions: const FileOptions(
                upsert: false,
                contentType: 'application/octet-stream',
                cacheControl: '0',
              ),
            ),
      );
    } finally {
      if (await exported.file.exists()) {
        await exported.file.delete();
      }
    }
  }

  Future<void> _downloadAndRestore({
    required String path,
    required String backupSecret,
    required int remoteRevision,
    required String organizationId,
    required String organizationName,
    String? expectedChecksum,
  }) async {
    status.value = const CloudSyncStatus(
      state: 'restoring',
      message: 'Mise à jour sécurisée depuis le cloud…',
    );

    // Réseau et déchiffrement se font avant le verrou : l'utilisateur n'est
    // bloqué que pendant le remplacement réel de SQLite.
    final encrypted = await _retryTransientNetwork(
      () => SupabaseBootstrap.client.storage.from(_bucket).download(path),
    );

    if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
      final actualChecksum = sha256.convert(encrypted).toString();
      if (actualChecksum != expectedChecksum) {
        throw StateError(
          'Le snapshot cloud est corrompu : checksum SHA-256 invalide.',
        );
      }
    }

    final compressed = await _decrypt(encrypted, backupSecret);
    final plain = Uint8List.fromList(gzip.decode(compressed));
    final tempDir = await getTemporaryDirectory();
    final source = File(
      p.join(
        tempDir.path,
        'gesapp-cloud-restore-${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await source.writeAsBytes(plain, flush: true);

    try {
      await SyncMaintenance.runExclusive(() async {
        final databasePath = await AppDatabase.instance.databasePath;
        await AppDatabase.instance.close();
        try {
          await _json.importAll(
            jsonPath: source.path,
            databasePath: databasePath,
            trustedSystem: true,
          );
        } finally {
          await AppDatabase.instance.initialize();
        }

        await _tenant.applyOrganizationIdentity(
          organizationId: organizationId,
          organizationName: organizationName,
        );

        final localRevision = await _tenant.localRevision();
        final now = DateTime.now();
        await _tenant.updateSyncState(
          lastUploadedLocalRevision: localRevision,
          knownRemoteRevision: remoteRevision,
          status: 'up_to_date',
          lastError: null,
          lastSyncedAt: now,
        );

        // Les écrans et tous les providers sont recréés sur la nouvelle base.
        SyncMaintenance.notifyDatabaseReplaced();
        status.value =
            CloudSyncStatus(state: 'up_to_date', lastSyncedAt: now);
      });
    } finally {
      if (await source.exists()) {
        await source.delete();
      }
    }
  }

  Future<Uint8List> _encrypt(List<int> bytes, String secret) async {
    final keyBytes = sha256.convert(utf8.encode(secret)).bytes;
    final nonce = List<int>.generate(
      _nonceLength,
      (_) => Random.secure().nextInt(256),
    );
    final box = await _aes.encrypt(
      bytes,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...utf8.encode(_magic),
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> _decrypt(List<int> bytes, String secret) async {
    final header = utf8.encode(_magic);
    if (bytes.length <= header.length + _nonceLength + 16) {
      throw StateError('Snapshot cloud incomplet.');
    }
    for (var i = 0; i < header.length; i++) {
      if (bytes[i] != header[i]) {
        throw StateError('Format de snapshot cloud invalide.');
      }
    }

    final nonceStart = header.length;
    final cipherStart = nonceStart + _nonceLength;
    final macStart = bytes.length - 16;
    final keyBytes = sha256.convert(utf8.encode(secret)).bytes;
    final clear = await _aes.decrypt(
      SecretBox(
        bytes.sublist(cipherStart, macStart),
        nonce: bytes.sublist(nonceStart, cipherStart),
        mac: Mac(bytes.sublist(macStart)),
      ),
      secretKey: SecretKey(keyBytes),
    );
    return Uint8List.fromList(clear);
  }
}
