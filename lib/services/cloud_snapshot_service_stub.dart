import 'package:flutter/foundation.dart';

class CloudSyncStatus {
  const CloudSyncStatus({required this.state, this.message, this.lastSyncedAt});
  final String state;
  final String? message;
  final DateTime? lastSyncedAt;
}

class CloudSnapshotService {
  CloudSnapshotService._();
  static final instance = CloudSnapshotService._();
  final ValueNotifier<CloudSyncStatus> status = ValueNotifier(const CloudSyncStatus(state: 'unsupported', message: 'Synchronisation de snapshot non disponible sur cette plateforme.'));
  void start() {}
  void stop() {}
  Future<void> synchronize({bool force = false}) async {}
}
