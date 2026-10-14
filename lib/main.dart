import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/gesapp_app.dart';
import 'core/db/app_database.dart';
import 'core/cloud/supabase_bootstrap.dart';
import 'core/platform/platform_database.dart';
import 'core/theme/theme_controller.dart';
import 'services/local_notification_service.dart';
import 'services/offline_background_service.dart';

Future<void> main() async {
  // Le binding et runApp restent dans la même zone. Les versions récentes de
  // Flutter signalent une "Zone mismatch" lorsqu'on initialise le binding
  // avant d'entrer dans runZonedGuarded, ce qui pouvait fragiliser le
  // démarrage de la release candidate.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LiquidGlassWidgets.initialize();
    configurePlatformDatabase();
    await SupabaseBootstrap.initializeIfConfigured();
    await AppDatabase.instance.initialize().timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException(
        "L'initialisation de la base de données a dépassé 8 secondes.",
      ),
    );
    await ThemeController.instance.load();
    await LocalNotificationService.instance.initialize();
    await OfflineBackgroundService.initialize();
    runApp(
      LiquidGlassWidgets.wrap(
        adaptiveQuality: true,
        respectSystemAccessibility: true,
        brightnessResolver: Theme.maybeBrightnessOf,
        theme: GlassThemeData.simple(
          blur: 10,
          thickness: 28,
          quality: GlassQuality.standard,
        ),
        child: const ProviderScope(child: GesApp()),
      ),
    );
  } catch (error, stackTrace) {
    runApp(_StartupErrorApp(error: error, stackTrace: stackTrace));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Erreur au démarrage')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'GesApp n’a pas pu démarrer correctement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fermez puis relancez l’application. Si le problème persiste, contactez le support sans supprimer les données locales.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('Détails techniques'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          'Erreur: $error\n\n$stackTrace',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
