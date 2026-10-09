import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'windows_ui.dart';

class WindowsPanel extends StatelessWidget {
  const WindowsPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (WindowsUi.isDesktop(context)) {
      final scheme = Theme.of(context).colorScheme;
      final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      );
      final content = Padding(padding: padding, child: child);
      return Material(
        color: scheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, child: content),
      );
    }
    final content = GlassCard(
      padding: padding,
      quality: GlassQuality.standard,
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class WindowsModuleCard extends StatelessWidget {
  const WindowsModuleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WindowsPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class WindowsModuleGrid extends StatelessWidget {
  const WindowsModuleGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1180 ? 3 : width >= 700 ? 2 : 1;
          final spacing = WindowsUi.isDesktop(context) ? 12.0 : 10.0;
          final itemWidth = (width - (columns - 1) * spacing) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [for (final child in children) SizedBox(width: itemWidth, child: child)],
          );
        },
      );
}
