import 'dart:async';

import 'package:flutter/material.dart';

import '../core/layout/responsive_layout.dart';
import '../core/session/operator_session.dart';
import '../core/theme/app_colors.dart';
import '../core/windows/windows_ui.dart';
import '../features/assets/assets_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/finance/finance_screen.dart';
import '../features/hr/hr_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/students/students_screen.dart';
import '../services/cloud_snapshot_service.dart';
import '../services/tenant_cloud_service.dart';
import '../services/platform_telemetry_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _NavEntry {
  const _NavEntry(this.icon, this.selectedIcon, this.label, this.page);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CloudSnapshotService.instance.start();
    PlatformTelemetryService.instance.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CloudSnapshotService.instance.stop();
    PlatformTelemetryService.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PlatformTelemetryService.instance.record(
        eventType: 'app_resumed',
        module: 'application',
        message: 'GesApp revenu au premier plan',
      ));
      unawaited(PlatformTelemetryService.instance.heartbeat());
      CloudSnapshotService.instance.synchronize();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Dans le flux multitenant courant, HomeShell est monté directement par
      // TenantAccessGate : la session n'est pas vidée ici et la synchronisation
      // d'arrière-plan reste donc valide. AppLockGate, lorsqu'il est utilisé,
      // synchronise de son côté avant de vider la session.
      CloudSnapshotService.instance.synchronize();
    }
  }

  List<_NavEntry> get _entries => _allEntries;

  void _select(int value) {
    if (value < 0 || value >= _entries.length) return;
    setState(() => _index = value);
    unawaited(PlatformTelemetryService.instance.moduleOpened(_entries[value].label));
  }

  static const _allEntries = [
    _NavEntry(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Accueil', DashboardScreen()),
    _NavEntry(Icons.school_outlined, Icons.school_rounded, 'Élèves', StudentsScreen()),
    _NavEntry(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Finances', FinanceScreen()),
    _NavEntry(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Dépenses', ExpensesScreen()),
    _NavEntry(Icons.groups_2_outlined, Icons.groups_2_rounded, 'RH', HrScreen()),
    _NavEntry(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Patrimoine', AssetsScreen()),
    _NavEntry(Icons.analytics_outlined, Icons.analytics_rounded, 'Rapports', ReportsScreen()),
    _NavEntry(Icons.tune_outlined, Icons.tune_rounded, 'Réglages', SettingsScreen()),
  ];

  static const _mobileIndexes = [0, 1, 2, 6];

  Future<void> _showMore(List<_NavEntry> entries) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tous les modules', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.sizeOf(context).width >= 520 ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.25,
              children: [3, 4, 5, 7]
                  .map((index) => InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, index),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(entries[index].selectedIcon, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 9),
                              Flexible(child: Text(entries[index].label, style: const TextStyle(fontWeight: FontWeight.w700))),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _select(selected);
  }

  Widget _pageContent(List<Widget> pages) {
    final content = IndexedStack(index: _index, children: pages);
    if (!OperatorSession.isAdmin) return content;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Mode Administrateur — consultation uniquement. Les données métier ne peuvent pas être modifiées.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await TenantCloudService.instance.signOut();
                      // TenantAccessGate écoute onAuthStateChange et remonte
                      // automatiquement l'écran de connexion. Ne pas forcer
                      // une seconde navigation pendant la désactivation de
                      // l'arbre Flutter.
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Déconnexion'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (_index >= entries.length) _index = 0;
    final pages = entries.map((e) => e.page).toList(growable: false);
    final destinations = entries
        .map((e) => NavigationDestination(icon: Icon(e.icon), selectedIcon: Icon(e.selectedIcon), label: e.label))
        .toList(growable: false);

    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= AppBreakpoints.tablet;
      if (!desktop) {
        final mobileDestinations = [
          for (final index in _mobileIndexes) destinations[index],
          const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Plus'),
        ];
        final mobileSelected = _mobileIndexes.indexOf(_index);
        return Scaffold(
          body: _pageContent(pages),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .7)))),
            child: NavigationBar(
              selectedIndex: mobileSelected < 0 ? 4 : mobileSelected,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (value) {
                if (value == 4) {
                  _showMore(entries);
                } else {
                  _select(_mobileIndexes[value]);
                }
              },
              destinations: mobileDestinations,
            ),
          ),
        );
      }

      if (WindowsUi.isNativeWindows) {
        final expanded = constraints.maxWidth >= WindowsUi.expandedPaneBreakpoint;
        return Scaffold(
          body: Row(
            children: [
              _WindowsNavigationPane(
                expanded: expanded,
                entries: entries,
                selectedIndex: _index,
                onSelected: _select,
              ),
              Expanded(child: _pageContent(pages)),
            ],
          ),
        );
      }

      final extended = constraints.maxWidth >= 1180;
      return Scaffold(
        body: Row(children: [
          SafeArea(
            child: Container(
              width: extended ? 250 : 88,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .06), blurRadius: 24, offset: const Offset(6, 0))],
              ),
              child: Column(children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: extended ? 10 : 4, vertical: 8),
                  child: Row(mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.navy, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white),
                    ),
                    if (extended) ...[
                      const SizedBox(width: 12),
                      const Expanded(child: Text('GesApp', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21))),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: NavigationRail(
                    extended: extended,
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    minWidth: 64,
                    minExtendedWidth: 215,
                    groupAlignment: -1,
                    destinations: entries.map((e) => NavigationRailDestination(icon: Icon(e.icon), selectedIcon: Icon(e.selectedIcon), label: Text(e.label))).toList(),
                  ),
                ),
              ]),
            ),
          ),
          VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1600), child: _pageContent(pages)),
            ),
          ),
        ]),
      );
    });
  }
}

class _WindowsNavigationPane extends StatelessWidget {
  const _WindowsNavigationPane({
    required this.expanded,
    required this.entries,
    required this.selectedIndex,
    required this.onSelected,
  });

  final bool expanded;
  final List<_NavEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = expanded ? WindowsUi.expandedPaneWidth : WindowsUi.compactPaneWidth;
    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: width,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: .8))),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 72,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 10),
                child: Row(
                  mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 21),
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GesApp', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            Text('Gestion scolaire', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .75)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (var i = 0; i < entries.length - 1; i++)
                    _WindowsNavItem(
                      entry: entries[i],
                      expanded: expanded,
                      selected: selectedIndex == i,
                      onTap: () => onSelected(i),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: _WindowsNavItem(
                entry: entries.last,
                expanded: expanded,
                selected: selectedIndex == entries.length - 1,
                onTap: () => onSelected(entries.length - 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowsNavItem extends StatelessWidget {
  const _WindowsNavItem({required this.entry, required this.expanded, required this.selected, required this.onTap});

  final _NavEntry entry;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: expanded ? '' : entry.label,
        child: Material(
          color: selected ? scheme.primaryContainer.withValues(alpha: .62) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onTap,
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  if (selected)
                    Container(
                      width: 3,
                      height: 20,
                      margin: EdgeInsets.only(left: expanded ? 2 : 0, right: expanded ? 9 : 0),
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(99)),
                    )
                  else if (expanded)
                    const SizedBox(width: 14),
                  Icon(selected ? entry.selectedIcon : entry.icon, size: 20, color: selected ? scheme.primary : foreground),
                  if (expanded) ...[
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: foreground, fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
