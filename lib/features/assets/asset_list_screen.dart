import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/asset.dart';
import 'asset_detail_screen.dart';
import 'asset_form_screen.dart';

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key});
  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  final _search = TextEditingController();
  String? _status;
  int _refresh = 0;

  Future<void> _open(Widget page) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() => _refresh++);
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(assetRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Biens & équipements')),
      floatingActionButton: OperatorSession.isReadOnly ? null : FloatingActionButton.extended(onPressed: () => _open(const AssetFormScreen()), icon: const Icon(Icons.add), label: const Text('Nouveau bien')),
      body: Column(children: [
        ResponsiveContent(
          maxWidth: 1200,
          padding: EdgeInsets.fromLTRB(ResponsiveLayout.pagePadding(context).left, 12, ResponsiveLayout.pagePadding(context).right, 8),
          child: ResponsiveFormRow(breakpoint: 620, children: [
            TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'N° inventaire, désignation, série, lieu…'), onChanged: (_) => setState(() {})),
            DropdownButtonFormField<String?>(initialValue: _status, decoration: const InputDecoration(labelText: 'Statut'), items: const [
              DropdownMenuItem(value: null, child: Text('Tous')),
              DropdownMenuItem(value: 'in_service', child: Text('En service')),
              DropdownMenuItem(value: 'stock', child: Text('En stock')),
              DropdownMenuItem(value: 'maintenance', child: Text('En maintenance')),
              DropdownMenuItem(value: 'out_of_service', child: Text('Hors service')),
              DropdownMenuItem(value: 'missing', child: Text('Manquant')),
              DropdownMenuItem(value: 'disposed', child: Text('Sorti du patrimoine')),
            ], onChanged: (v) => setState(() => _status = v)),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<AssetItem>>(
            key: ValueKey('$_refresh-${_search.text}-$_status'),
            future: repo.assets(query: _search.text, status: _status, limit: 500),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final items = snapshot.data!;
              if (items.isEmpty) return const Center(child: Text('Aucun bien ne correspond à la recherche.'));
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(ResponsiveLayout.pagePadding(context).left, 4, ResponsiveLayout.pagePadding(context).right, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final a = items[i];
                  return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: Card(child: ListTile(
                    leading: CircleAvatar(child: Icon(_iconForStatus(a.status))),
                    title: Text('${a.assetNumber} · ${a.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${a.categoryName} · ${a.locationName ?? 'Non localisé'}${a.employeeName == null ? '' : ' · ${a.employeeName}'}\nÉtat: ${_conditionLabel(a.condition)} · Valeur: ${formatXaf(a.acquisitionValue)}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(AssetDetailScreen(assetId: a.id)),
                  ))));
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  IconData _iconForStatus(String status) => switch (status) {
    'maintenance' => Icons.build_outlined,
    'out_of_service' => Icons.report_problem_outlined,
    'missing' => Icons.search_off_outlined,
    'disposed' => Icons.archive_outlined,
    'stock' => Icons.inventory_outlined,
    _ => Icons.check_circle_outline,
  };

  String _conditionLabel(String condition) => switch (condition) {
    'new' => 'Neuf', 'good' => 'Bon', 'fair' => 'Moyen', 'repair' => 'À réparer', 'broken' => 'Hors service', _ => condition,
  };
}
