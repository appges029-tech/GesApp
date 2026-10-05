import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/asset.dart';
import 'asset_configuration_screen.dart';
import 'asset_inventory_screen.dart';
import 'asset_list_screen.dart';
import 'asset_maintenance_screen.dart';
import 'asset_reports_screen.dart';

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  int _refresh = 0;

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return WindowsPageScaffold(
      title: 'Patrimoine',
      subtitle: 'Biens, affectations, maintenance et inventaires',
      actions: [
        WindowsCommandButton(icon: Icons.refresh, label: 'Actualiser', onPressed: () => setState(() => _refresh++)),
        WindowsCommandButton(icon: Icons.settings_outlined, label: 'Configuration', onPressed: () => _open(const AssetConfigurationScreen())),
      ],
      body: FutureBuilder<AssetSummary>(
        key: ValueKey(_refresh),
        future: ref.read(assetRepositoryProvider).summary(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final summary = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _refresh++),
            child: ListView(
              padding: WindowsUi.isDesktop(context) ? EdgeInsets.zero : const EdgeInsets.all(16),
              children: [
                LayoutBuilder(builder: (context, box) {
                  final columns = box.maxWidth >= 1100 ? 4 : box.maxWidth >= 650 ? 2 : 1;
                  const gap = 10.0;
                  final width = (box.maxWidth - ((columns - 1) * gap)) / columns;
                  final cards = [
                    _Kpi('Biens enregistrés', '${summary.total}', Icons.inventory_2_outlined),
                    _Kpi('En service', '${summary.inService}', Icons.check_circle_outline),
                    _Kpi('En maintenance', '${summary.maintenance}', Icons.build_outlined),
                    _Kpi('Hors service', '${summary.outOfService}', Icons.report_problem_outlined),
                    _Kpi('Manquants', '${summary.missing}', Icons.search_off_outlined),
                    _Kpi('Garanties ≤ 30 j', '${summary.warrantyExpiring}', Icons.shield_outlined),
                    _Kpi('Inventaires ouverts', '${summary.openInventories}', Icons.fact_check_outlined),
                    _Kpi('Valeur d’acquisition', formatXaf(summary.totalAcquisitionValue), Icons.account_balance_outlined),
                  ];
                  return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: width, child: card)]);
                }),
                const SizedBox(height: 22),
                Text('Modules', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                WindowsModuleGrid(children: [
                  WindowsModuleCard(icon: Icons.inventory_2_outlined, title: 'Biens & équipements', subtitle: 'Registre patrimonial, affectations, localisation, état et historique.', onTap: () => _open(const AssetListScreen())),
                  WindowsModuleCard(icon: Icons.build_circle_outlined, title: 'Maintenance', subtitle: 'Pannes, interventions, coûts, prestataires et prochaines maintenances.', onTap: () => _open(const AssetMaintenanceScreen())),
                  WindowsModuleCard(icon: Icons.fact_check_outlined, title: 'Inventaires physiques', subtitle: 'Campagnes d’inventaire, biens trouvés, déplacés, endommagés ou manquants.', onTap: () => _open(const AssetInventoryScreen())),
                  WindowsModuleCard(icon: Icons.analytics_outlined, title: 'Rapports patrimoniaux', subtitle: 'Valeur et effectifs par catégorie, localisation et statut.', onTap: () => _open(const AssetReportsScreen())),
                  WindowsModuleCard(icon: Icons.tune_outlined, title: 'Catégories & localisations', subtitle: 'Sites, bâtiments, étages, salles, dépôts et familles de biens.', onTap: () => _open(const AssetConfigurationScreen())),
                ]),
                const SizedBox(height: 28),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => WindowsPanel(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
        ]),
      );
}
