import 'package:flutter/material.dart';
import '../../core/theme/theme_controller.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Apparence')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Thème de l’application', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Choisissez un affichage clair, sombre ou synchronisé avec le téléphone.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _ThemeChoice(
              icon: Icons.brightness_auto_rounded,
              title: 'Système',
              subtitle: 'Suit automatiquement le thème du téléphone',
              selected: controller.mode == ThemeMode.system,
              onTap: () => controller.setMode(ThemeMode.system),
            ),
            const SizedBox(height: 10),
            _ThemeChoice(
              icon: Icons.light_mode_rounded,
              title: 'Mode clair',
              subtitle: 'Interface lumineuse et nette',
              selected: controller.mode == ThemeMode.light,
              onTap: () => controller.setMode(ThemeMode.light),
            ),
            const SizedBox(height: 10),
            _ThemeChoice(
              icon: Icons.dark_mode_rounded,
              title: 'Mode sombre',
              subtitle: 'Confort visuel dans les environnements sombres',
              selected: controller.mode == ThemeMode.dark,
              onTap: () => controller.setMode(ThemeMode.dark),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer.withValues(alpha: .55) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: selected ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ])),
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? scheme.primary : scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
