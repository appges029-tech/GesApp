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
import '../core/session/tenant_subscription_access.dart';
import '../data/repositories/tenant_repository.dart';
import 'json_data_service.dart';
import 'platform_telemetry_service.dart';

class CloudSyncStatus {
  const CloudSyncStatus({required this.state, this.message, this.lastSyncedAt});
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

  final ValueNotifier<CloudSyncStatus> status = ValueNotifier(
    const CloudSyncStatus(state: 'idle'),
  );

  void start() {
    _timer?.cancel();
    // Une tentative immédiate, puis toutes les dix minutes tant que GesApp
    // reste ouvert. Un échec réseau n'empêche jamais le travail local.
    unawaited(synchronize());
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(synchronize()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> resolveConflictUsingCloud() async {
    if (OperatorSession.organizationId != null &&
        !TenantSubscriptionAccess.instance.isAllowed) return;
    if (_running || !OperatorSession.isAuthenticated || !SupabaseBootstrap.isInitialized) return;
    final orgId = OperatorSession.organizationId;
    if (orgId == null) return;

    _running = true;
    status.value = const CloudSyncStatus(
      state: 'restoring',
      message: 'Restauration de la version cloud…',
    );
    try {
      final membership = await _tenant.cachedMembership();
      final secret = membership?.backupSecret;
      if (membership == null || secret == null || secret.length < 16) {
        throw StateError('Clé de sauvegarde de l’établissement indisponible.');
      }

      final metadata = await _remoteMetadata(orgId);
      final remoteRevision = (metadata?['revision'] as num?)?.toInt() ?? 0;
      final remotePath = metadata?['current_path']?.toString();
      if (remotePath == null || remotePath.isEmpty || remoteRevision <= 0) {
        throw StateError('Aucune version cloud exploitable n’est disponible.');
      }

      await _downloadAndRestore(
        path: remotePath,
        backupSecret: secret,
        remoteRevision: remoteRevision,
        expectedChecksum: metadata?['checksum_sha256']?.toString(),
      );
    } catch (e) {
      final message = _syncErrorMessage(e);
      await _tenant.updateSyncState(status: 'error', lastError: message);
      status.value = CloudSyncStatus(state: 'error', message: message);
      unawaited(PlatformTelemetryService.instance.record(
        eventType: 'sync_error',
        module: 'synchronisation',
        message: message,
      ));
    } finally {
      _running = false;
    }
  }

  Future<void> resolveConflictKeepingLocal() async {
    if (OperatorSession.organizationId != null &&
        !TenantSubscriptionAccess.instance.isAllowed) return;
    if (!OperatorSession.isManager) {
      status.value = const CloudSyncStatus(
        state: 'error',
        message: 'Seul un gestionnaire peut publier la version locale.',
      );
      return;
    }
    if (_running || !OperatorSession.isAuthenticated || !SupabaseBootstrap.isInitialized) return;
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
    } catch (e) {
      final message = _syncErrorMessage(e);
      await _tenant.updateSyncState(status: 'error', lastError: message);
      status.value = CloudSyncStatus(state: 'error', message: message);
      unawaited(PlatformTelemetryService.instance.record(
        eventType: 'sync_error',
        module: 'synchronisation',
        message: message,
      ));
      return;
    } finally {
      _running = false;
    }

    // Une nouvelle lecture des métadonnées est faite dans synchronize().
    // Si un troisième appareil a publié entre-temps, le conflit sera détecté
    // à nouveau au lieu d'écraser silencieusement sa version.
    await synchronize(force: true);
  }

  Future<void> synchronize({bool force = false}) async {
    if (OperatorSession.organizationId != null &&
        !TenantSubscriptionAccess.instance.isAllowed) {
      status.value = const CloudSyncStatus(
        state: 'blocked',
        message: 'Synchronisation bloquée : abonnement expiré.',
      );
      return;
    }
    if (_running || !OperatorSession.isAuthenticated || !SupabaseBootstrap.isInitialized) return;
    final orgId = OperatorSession.organizationId;
    if (orgId == null) return;
    _running = true;
    status.value = const CloudSyncStatus(state: 'syncing', message: 'Synchronisation en cours…');
    try {
      final membership = await _tenant.cachedMembership();
      final secret = membership?.backupSecret;
      if (membership == null || secret == null || secret.length < 16) {
        throw StateError('Clé de sauvegarde de l’établissement indisponible.');
      }
      final state = await _tenant.syncState();
      final localRevision = (state['local_revision'] as int?) ?? 0;
      final lastUploaded = (state['last_uploaded_local_revision'] as int?) ?? 0;
      final knownRemote = (state['known_remote_revision'] as int?) ?? 0;
      final metadata = await _remoteMetadata(orgId);
      final remoteRevision = (metadata?['revision'] as num?)?.toInt() ?? 0;
      final remotePath = metadata?['current_path']?.toString();
      final remoteChecksum = metadata?['checksum_sha256']?.toString();

      // L'administrateur est strictement lecteur du cloud : la version distante
      // est donc la source de vérité. Une migration locale peut incrémenter
      // local_revision sans représenter une modification métier à publier ; ce
      // bruit technique ne doit jamais bloquer la restauration d'un snapshot
      // cloud plus récent pour un administrateur.
      if (OperatorSession.isAdmin) {
        if (remotePath != null && remotePath.isNotEmpty && remoteRevision > knownRemote) {
          await _downloadAndRestore(
            path: remotePath,
            backupSecret: secret,
            remoteRevision: remoteRevision,
            expectedChecksum: remoteChecksum,
          );
        } else {
          status.value = CloudSyncStatus(state: 'up_to_date', lastSyncedAt: DateTime.now());
        }
        return;
      }

      final localDirty = localRevision != lastUploaded;

      // Pour un gestionnaire, protéger les changements locaux reste prioritaire :
      // une version cloud concurrente déclenche un conflit explicite.
      if (remoteRevision > knownRemote && remotePath != null && remotePath.isNotEmpty) {
        if (!localDirty) {
          await _downloadAndRestore(
            path: remotePath,
            backupSecret: secret,
            remoteRevision: remoteRevision,
            expectedChecksum: remoteChecksum,
          );
          return;
        }
        await _tenant.updateSyncState(
          status: 'conflict',
          lastError: 'Une version cloud plus récente existe alors que cet appareil contient aussi des modifications locales.',
        );
        status.value = const CloudSyncStatus(
          state: 'conflict',
          message: 'Conflit détecté : aucune donnée n’a été écrasée. Synchronisez d’abord l’appareil le plus récent.',
        );
        unawaited(PlatformTelemetryService.instance.record(
          eventType: 'sync_conflict',
          module: 'synchronisation',
          message: 'Conflit local/cloud détecté',
          metadata: {'remote_revision': remoteRevision},
        ));
        return;
      }

      final needsInitialUpload = remotePath == null || remotePath.isEmpty;
      if (!force && !localDirty && !needsInitialUpload) {
        await _tenant.updateSyncState(
          knownRemoteRevision: remoteRevision,
          status: 'up_to_date',
          lastError: null,
          lastSyncedAt: DateTime.now(),
        );
        status.value = CloudSyncStatus(state: 'up_to_date', lastSyncedAt: DateTime.now());
        return;
      }

      final exported = await _json.exportAll(await AppDatabase.instance.databasePath, trustedSystem: true);
      try {
        final rawSnapshot = await exported.file.readAsBytes();
        final compressedSnapshot = gzip.encode(rawSnapshot);
        final encrypted = await _encrypt(compressedSnapshot, secret);
        final nextRemote = remoteRevision + 1;
        final uniqueSuffix = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
        final storagePath = '$orgId/snapshot-$nextRemote-$uniqueSuffix.gesync';
        await SupabaseBootstrap.client.storage.from(_bucket).uploadBinary(
          storagePath,
          encrypted,
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'application/octet-stream',
            cacheControl: '0',
          ),
        );
        final checksum = sha256.convert(encrypted).toString();
        final now = DateTime.now();
        var metadataCommitted = false;
        try {
          if (metadata == null) {
            await SupabaseBootstrap.client.from('sync_metadata').insert({
              'organization_id': orgId,
              'revision': nextRemote,
              'current_path': storagePath,
              'checksum_sha256': checksum,
              'size_bytes': encrypted.length,
              'uploaded_by': OperatorSession.cloudUserId,
              'uploaded_at': now.toUtc().toIso8601String(),
              'updated_at': now.toUtc().toIso8601String(),
            });
            metadataCommitted = true;
          } else {
            final updated = await SupabaseBootstrap.client
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
                .select('revision');
            metadataCommitted = updated.isNotEmpty;
            if (!metadataCommitted) {
              throw StateError('La sauvegarde cloud a changé pendant l’envoi. Nouvelle tentative requise.');
            }
          }
        } finally {
          if (!metadataCommitted) {
            try {
              await SupabaseBootstrap.client.storage.from(_bucket).remove([storagePath]);
            } catch (_) {
              // Le fichier orphelin pourra être nettoyé plus tard ; ne jamais
              // masquer l'erreur de concurrence qui protège les données.
            }
          }
        }
        // La métadonnée pointe désormais de façon atomique vers notre fichier.
        // On peut supprimer l'ancien snapshot sans risque de casser la version
        // publiée par un autre appareil.
        if (metadataCommitted && remotePath != null && remotePath.isNotEmpty && remotePath != storagePath) {
          try {
            await SupabaseBootstrap.client.storage.from(_bucket).remove([remotePath]);
          } catch (_) {
            // Nettoyage non critique : la cohérence dépend de current_path.
          }
        }
        final currentLocalRevision = await _tenant.localRevision();
        await _tenant.updateSyncState(
          lastUploadedLocalRevision: currentLocalRevision,
          knownRemoteRevision: nextRemote,
          status: 'up_to_date',
          lastError: null,
          lastSyncedAt: now,
        );
        status.value = CloudSyncStatus(state: 'up_to_date', lastSyncedAt: now);
        unawaited(PlatformTelemetryService.instance.record(
          eventType: 'sync_uploaded',
          module: 'synchronisation',
          message: 'Nouvelle révision publiée vers le cloud',
          metadata: {'revision': nextRemote, 'size_bytes': encrypted.length},
        ));
      } finally {
        if (await exported.file.exists()) await exported.file.delete();
      }
    } catch (e) {
      final message = _syncErrorMessage(e);
      await _tenant.updateSyncState(status: 'error', lastError: message);
      status.value = CloudSyncStatus(state: 'error', message: message);
      unawaited(PlatformTelemetryService.instance.record(
        eventType: 'sync_error',
        module: 'synchronisation',
        message: message,
      ));
    } finally {
      _running = false;
    }
  }

  Future<Map<String, dynamic>?> _remoteMetadata(String orgId) async {
    final rows = await _retryTransientNetwork(
      () => SupabaseBootstrap.client
          .from('sync_metadata')
          .select('revision,current_path,checksum_sha256,size_bytes,uploaded_at')
          .eq('organization_id', orgId)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<T> _retryTransientNetwork<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } catch (error) {
        lastError = error;
        if (!_isTransientNetworkError(error) || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 450 * (attempt + 1)));
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
        raw.contains('timeoutexception');
  }

  String _syncErrorMessage(Object error) {
    if (_isTransientNetworkError(error)) {
      return 'Connexion Internet temporairement indisponible. '
          'Vos données restent enregistrées sur cet appareil. '
          'GesApp réessaiera automatiquement et vous pouvez aussi toucher '
          '« Synchroniser maintenant » lorsque la connexion revient.';
    }
    return error.toString();
  }

  Future<void> _downloadAndRestore({
    required String path,
    required String backupSecret,
    required int remoteRevision,
    String? expectedChecksum,
  }) async {
    status.value = const CloudSyncStatus(state: 'restoring', message: 'Mise à jour depuis le cloud…');
    final encrypted = await _retryTransientNetwork(
      () => SupabaseBootstrap.client.storage.from(_bucket).download(path),
    );
    if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
      final actualChecksum = sha256.convert(encrypted).toString();
      if (actualChecksum != expectedChecksum) {
        throw StateError('Le snapshot cloud est corrompu : checksum SHA-256 invalide.');
      }
    }
    final compressed = await _decrypt(encrypted, backupSecret);
    final plain = Uint8List.fromList(gzip.decode(compressed));
    final tempDir = await getTemporaryDirectory();
    final source = File(p.join(tempDir.path, 'gesapp-cloud-restore-${DateTime.now().millisecondsSinceEpoch}.json'));
    await source.writeAsBytes(plain, flush: true);
    try {
      final databasePath = await AppDatabase.instance.databasePath;
      await AppDatabase.instance.close();
      try {
        await _json.importAll(jsonPath: source.path, databasePath: databasePath, trustedSystem: true);
      } finally {
        await AppDatabase.instance.initialize();
      }
      final localRevision = await _tenant.localRevision();
      await _tenant.updateSyncState(
        lastUploadedLocalRevision: localRevision,
        knownRemoteRevision: remoteRevision,
        status: 'up_to_date',
        lastError: null,
        lastSyncedAt: DateTime.now(),
      );
      status.value = CloudSyncStatus(state: 'up_to_date', lastSyncedAt: DateTime.now());
      unawaited(PlatformTelemetryService.instance.record(
        eventType: 'sync_downloaded',
        module: 'synchronisation',
        message: 'Révision cloud restaurée sur l’appareil',
        metadata: {'revision': remoteRevision, 'size_bytes': encrypted.length},
      ));
    } finally {
      if (await source.exists()) await source.delete();
    }
  }

  Future<Uint8List> _encrypt(List<int> bytes, String secret) async {
    final keyBytes = sha256.convert(utf8.encode(secret)).bytes;
    final nonce = List<int>.generate(_nonceLength, (_) => Random.secure().nextInt(256));
    final box = await _aes.encrypt(bytes, secretKey: SecretKey(keyBytes), nonce: nonce);
    return Uint8List.fromList([
      ...utf8.encode(_magic),
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> _decrypt(List<int> bytes, String secret) async {
    final header = utf8.encode(_magic);
    if (bytes.length <= header.length + _nonceLength + 16) throw StateError('Snapshot cloud incomplet.');
    for (var i = 0; i < header.length; i++) {
      if (bytes[i] != header[i]) throw StateError('Format de snapshot cloud invalide.');
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
