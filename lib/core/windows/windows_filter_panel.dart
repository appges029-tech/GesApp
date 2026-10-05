import 'package:flutter/material.dart';

import 'windows_panels.dart';
import 'windows_ui.dart';

class WindowsFilterPanel extends StatelessWidget {
  const WindowsFilterPanel({
    super.key,
    required this.search,
    required this.filters,
    this.active = false,
    this.onClear,
    this.onApply,
  });

  final Widget search;
  final List<Widget> filters;
  final bool active;
  final VoidCallback? onClear;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    if (!WindowsUi.isDesktop(context)) {
      return Column(
        children: [
          search,
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Filtres avancés${active ? ' • actifs' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            leading: const Icon(Icons.tune),
            children: [
              for (var i = 0; i < filters.length; i++) ...[
                filters[i],
                if (i != filters.length - 1) const SizedBox(height: 8),
              ],
              if (onClear != null || onApply != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (onClear != null) Expanded(child: OutlinedButton.icon(onPressed: onClear, icon: const Icon(Icons.clear_all), label: const Text('Effacer'))),
                    if (onClear != null && onApply != null) const SizedBox(width: 8),
                    if (onApply != null) Expanded(child: FilledButton.icon(onPressed: onApply, icon: const Icon(Icons.filter_alt), label: const Text('Appliquer'))),
                  ],
                ),
              ],
            ],
          ),
        ],
      );
    }

    return WindowsPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          if (filters.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100 ? 4 : constraints.maxWidth >= 760 ? 3 : 2;
                const gap = 10.0;
                final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [for (final filter in filters) SizedBox(width: width, child: filter)],
                );
              },
            ),
          ],
          if (onClear != null || onApply != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onClear != null) OutlinedButton.icon(onPressed: onClear, icon: const Icon(Icons.clear_all, size: 18), label: const Text('Effacer')),
                if (onClear != null && onApply != null) const SizedBox(width: 8),
                if (onApply != null) FilledButton.icon(onPressed: onApply, icon: const Icon(Icons.filter_alt, size: 18), label: const Text('Appliquer')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
