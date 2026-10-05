import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/db/app_database.dart';
import '../core/platform/platform_database.dart';
import '../data/repositories/alerts_repository.dart';
import 'local_notification_service.dart';
import 'automatic_backup_service.dart';

const _offlineAlertTask = 'gesapp.offline.alert.refresh';

@pragma('vm:entry-point')
void gesAppBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      configurePlatformDatabase();
      await AppDatabase.instance.initialize();
      await AlertsRepository(AppDatabase.instance).refreshOperationalAlerts();
      await LocalNotificationService.instance.initialize();
      await LocalNotificationService.instance.publishPendingAlerts();
      await AutomaticBackupService.runIfDue();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class OfflineBackgroundService {
  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().initialize(gesAppBackgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      'gesapp-offline-alerts-periodic',
      _offlineAlertTask,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }
}
