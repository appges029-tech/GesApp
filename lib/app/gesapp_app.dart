import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/theme/liquid_glass_backdrop.dart';
import '../core/session/operator_session.dart';
import '../features/security/tenant_access_gate.dart';
import '../features/security/tenant_subscription_overlay.dart';
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
        builder: (context, child) => ValueListenableBuilder<int>(
          valueListenable: OperatorSession.changes,
          builder: (context, _, __) => GlassPage(
            background: const LiquidGlassBackdrop(),
            enableBackgroundSampling: true,
            edgeToEdge: true,
            statusBarStyle: GlassStatusBarStyle.auto,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GlassNavigationShell(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                if (OperatorSession.isReadOnly)
                  const _AdminReadOnlyBadge(),
                const TenantSubscriptionOverlay(),
              ],
            ),
          ),
        ),
        home: const TenantAccessGate(),
      ),
    );
  }
}


class _AdminReadOnlyBadge extends StatelessWidget {
  const _AdminReadOnlyBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top + 6;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 15, color: scheme.onSecondaryContainer),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Lecture seule · Administrateur',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
