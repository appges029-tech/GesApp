import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/cloud/supabase_bootstrap.dart';
import '../core/session/operator_session.dart';

class PlatformTelemetryService {
  PlatformTelemetryService._();
  static final instance = PlatformTelemetryService._();

  Timer? _heartbeatTimer;
  String? _deviceKey;

  void start() {
    _heartbeatTimer?.cancel();
    unawaited(record(
      eventType: 'app_open',
      module: 'application',
      message: 'GesApp ouvert',
    ));
    unawaited(heartbeat());
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(heartbeat()),
    );
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(record(
      eventType: 'app_close',
      module: 'application',
      message: 'GesApp fermé ou mis en arrière-plan',
    ));
  }

  Future<void> heartbeat() async {
    if (!SupabaseBootstrap.isInitialized || !OperatorSession.isAuthenticated) {
      return;
    }
    final organizationId = OperatorSession.organizationId;
    final userId = OperatorSession.cloudUserId;
    if (organizationId == null || userId == null) return;

    try {
      final key = await _getDeviceKey();
      await SupabaseBootstrap.client.from('devices').upsert({
        'organization_id': organizationId,
        'user_id': userId,
        'device_key': key,
        'platform': _platformName(),
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'organization_id,device_key');
    } catch (_) {
      // La télémétrie ne doit jamais bloquer le fonctionnement offline.
    }
  }

  Future<void> record({
    required String eventType,
    required String module,
    String? message,
    Map<String, Object?> metadata = const {},
  }) async {
    if (!SupabaseBootstrap.isInitialized || !OperatorSession.isAuthenticated) {
      return;
    }
    final organizationId = OperatorSession.organizationId;
    final userId = OperatorSession.cloudUserId;
    if (organizationId == null || userId == null) return;

    try {
      await SupabaseBootstrap.client.from('platform_activity_events').insert({
        'organization_id': organizationId,
        'actor_user_id': userId,
        'event_type': eventType,
        'module': module,
        'message': message,
        'metadata': metadata,
      });
    } catch (_) {
      // Journal central best-effort : aucune erreur réseau ne remonte à l'UI.
    }
  }

  Future<void> moduleOpened(String module) {
    return record(
      eventType: 'module_opened',
      module: module.toLowerCase(),
      message: 'Module $module consulté',
    );
  }

  Future<String> _getDeviceKey() async {
    if (_deviceKey != null) return _deviceKey!;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('gesapp_platform_device_key');
    if (existing != null && existing.isNotEmpty) {
      _deviceKey = existing;
      return existing;
    }
    final created = const Uuid().v4();
    await prefs.setString('gesapp_platform_device_key', created);
    _deviceKey = created;
    return created;
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
