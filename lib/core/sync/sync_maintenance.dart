import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coordonne les opérations qui remplacent entièrement la base locale.
///
/// Pendant une restauration cloud, aucune nouvelle écriture métier ne doit
/// démarrer. Le compteur permet d'imbriquer proprement des opérations système.
abstract final class SyncMaintenance {
  static int _depth = 0;

  static bool get isActive => _depth > 0;

  static final ValueNotifier<int> dataEpoch = ValueNotifier<int>(0);

  static Future<T> runExclusive<T>(Future<T> Function() action) async {
    _depth++;
    try {
      // Laisse finir les opérations SQLite déjà engagées avant la fermeture
      // de la base. Les nouvelles écritures sont bloquées par BusinessWriteGuard.
      await Future<void>.delayed(Duration.zero);
      return await action();
    } finally {
      _depth--;
    }
  }

  static void notifyDatabaseReplaced() {
    dataEpoch.value++;
  }
}
