import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/finance.dart';

class FeeCategoriesScreen extends ConsumerWidget {
  const FeeCategoriesScreen({super.key});

  Future<Map<String, String>?> _categoryDialog(
    BuildContext context, {
    required String title,
    String initialName = '',
    String initialPeriodicity = 'mensuelle',
  }) async {
    String name = initialName;
    String periodicity = initialPeriodicity;
    String? error;
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                initialValue: initialName,
                decoration: InputDecoration(labelText: 'Nom *', errorText: error),
                onChanged: (value) => name = value,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: periodicity,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Périodicité'),
                items: const [
                  DropdownMenuItem(value: 'mensuelle', child: Text('Mensuelle')),
                  DropdownMenuItem(value: 'trimestrielle', child: Text('Trimestrielle')),
                  DropdownMenuItem(value: 'annuelle', child: Text('Annuelle')),
                  DropdownMenuItem(value: 'unique', child: Text('Paiement unique')),
                ],
                onChanged: (value) {
                  if (value != null) update(() => periodicity = value);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Les périodes de paiement seront proposées automatiquement '
                'à partir du tarif et de l’année scolaire.',
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (name.trim().isEmpty) {
                  update(() => error = 'Le nom est obligatoire.');
                  return;
                }
                Navigator.pop(dialogContext, {'name': name.trim(), 'periodicity': periodicity});
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final input = await _categoryDialog(context, title: 'Nouvelle rubrique');
    if (input == null || !context.mounted) return;
    try {
      await ref.read(financeRepositoryProvider).addFeeCategory(
        name: input['name']!,
        periodicity: input['periodicity']!,
      );
      ref.invalidate(feeCategoriesProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Création impossible : $error')),
        );
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, FeeCategoryItem item) async {
    final input = await _categoryDialog(
      context,
      title: 'Modifier la rubrique',
      initialName: item.name,
      initialPeriodicity: item.periodicity,
    );
    if (input == null || !context.mounted) return;
    try {
      await ref.read(financeRepositoryProvider).updateFeeCategory(
        feeId: item.id,
        name: input['name']!,
        periodicity: input['periodicity']!,
      );
      ref.invalidate(feeCategoriesProvider);
      ref.invalidate(feeGridProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Modification impossible : $error')),
        );
      }
    }
  }

  Future<void> _deactivate(
    BuildContext context,
    WidgetRef ref,
    FeeCategoryItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Désactiver la rubrique ?'),
        content: Text(
          '« ${item.name} » ne sera plus proposée pour de nouvelles obligations. '
          'Les échéances déjà créées restent intactes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(financeRepositoryProvider).deactivateFeeCategory(item.id);
      ref.invalidate(feeCategoriesProvider);
      ref.invalidate(feeGridProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Désactivation impossible : $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fees = ref.watch(feeCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rubriques de paiement')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Rubrique'),
      ),
      body: fees.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('Aucune rubrique configurée.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16).copyWith(bottom: 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: Text(
                      items[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Périodicité : ${items[i].periodicity}\nAppui long pour désactiver',
                    ),
                    isThreeLine: true,
                    onTap: () => _edit(context, ref, items[i]),
                    onLongPress: () => _deactivate(context, ref, items[i]),
                  ),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : $error')),
      ),
    );
  }
}
