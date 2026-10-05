import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../features/security/tenant_access_gate.dart';
import 'app_navigation.dart';

class GesApp extends StatelessWidget {
  const GesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;
    final windows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        title: 'GesApp',
        theme: windows ? AppTheme.windowsLight : AppTheme.light,
        darkTheme: windows ? AppTheme.windowsDark : AppTheme.dark,
        themeMode: controller.mode,
        home: const TenantAccessGate(),
      ),
    );
  }
}
