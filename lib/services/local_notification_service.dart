import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/db/app_database.dart';
import '../core/session/business_write_guard.dart';
import '../core/session/operator_session.dart';
import '../app/app_navigation.dart';
import '../features/notifications/notifications_screen.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;
  bool get isSupported => !kIsWeb && (_isAndroid || _isWindows);
  bool get isInitialized => _initialized;
  String get platformLabel => _isWindows ? 'Windows' : _isAndroid ? 'Android' : 'cette plateforme';

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'GesApp',
      appUserModelId: 'GodFirst.GesApp',
      guid: 'f54f6a36-4d74-4e5f-b4bc-b26d94a54dc7',
    );
    const settings = InitializationSettings(
      android: android,
      windows: windows,
    );
    await _plugin.initialize(settings: settings, onDidReceiveNotificationResponse: (_) {
      final nav=appNavigatorKey.currentState;
      if(nav!=null) nav.push(MaterialPageRoute(builder:(_)=>const NotificationsScreen()));
    });

    if (_isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
    _initialized = true;
  }

  Future<bool> isEnabled() async {
    final rows = await AppDatabase.instance.db.query('app_settings', where: 'key = ?', whereArgs: ['offline_notifications'], limit: 1);
    if (rows.isEmpty) return true;
    return rows.first['value'] != 'off';
  }

  Future<void> setEnabled(bool enabled) async {
    BusinessWriteGuard.ensureAllowed('setOfflineNotificationsEnabled');
    final now = DateTime.now().toIso8601String();
    await AppDatabase.instance.db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings(key,value,updated_at) VALUES(?,?,?)',
        ['offline_notifications', enabled ? 'on' : 'off', now],
      );
      await txn.insert('audit_log', {
        'entity_type': 'app_settings',
        'entity_id': 'offline_notifications',
        'action': 'update',
        'new_value': enabled ? 'on' : 'off',
        'operator_name': OperatorSession.current,
        'operator_id': OperatorSession.userId,
        'operator_role': OperatorSession.role,
        'created_at': now,
      });
    });
    if (!enabled && isSupported) await _plugin.cancelAll();
  }

  Future<int> publishPendingAlerts({int limit = 12}) async {
    if (!isSupported || !await isEnabled()) return 0;
    if (!_initialized) await initialize();

    final rows = await AppDatabase.instance.db.query(
      'alerts',
      where: "notification_sent = 0 AND is_read = 0 AND status != 'archived' AND status != 'resolved'",
      orderBy: "CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END, created_at DESC",
      limit: limit,
    );
    var sent = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final title = row['title'] as String;
      final message = row['message'] as String;
      final severity = (row['severity'] as String?) ?? 'warning';
      await _plugin.show(
        id: _stableId(id),
        title: title,
        body: message,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            severity == 'critical' || severity == 'high' ? 'gesapp_urgent' : 'gesapp_alerts',
            severity == 'critical' || severity == 'high' ? 'Alertes prioritaires GesApp' : 'Alertes GesApp',
            channelDescription: 'Notifications locales générées par GesApp sans connexion Internet.',
            importance: severity == 'critical' ? Importance.max : severity == 'high' ? Importance.high : Importance.defaultImportance,
            priority: severity == 'critical' ? Priority.max : severity == 'high' ? Priority.high : Priority.defaultPriority,
            onlyAlertOnce: true,
            category: AndroidNotificationCategory.reminder,
          ),
          windows: const WindowsNotificationDetails(),
        ),
        payload: '${row['target_type'] ?? ''}:${row['target_id'] ?? ''}',
      );
      await AppDatabase.instance.db.update('alerts', {'notification_sent': 1}, where: 'id = ?', whereArgs: [id]);
      sent++;
    }
    return sent;
  }

  Future<void> showTestNotification() async {
    if (!isSupported) {
      throw UnsupportedError('Les notifications système ne sont pas disponibles sur $platformLabel.');
    }
    if (!_initialized) await initialize();
    await _plugin.show(
      id: 909090,
      title: 'Notifications GesApp activées',
      body: 'Cette notification a été générée entièrement hors ligne sur cet appareil.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'gesapp_alerts',
          'Alertes GesApp',
          channelDescription: 'Notifications locales générées par GesApp sans connexion Internet.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  int _stableId(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = ((hash * 31) + code) & 0x7fffffff;
    }
    return hash;
  }
}
