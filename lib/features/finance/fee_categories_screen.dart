import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/finance.dart';

class FeeCategoriesScreen extends ConsumerWidget {
  const FeeCategoriesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    String periodicity = 'mensuelle';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouvelle rubrique'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  hintText: 'Frais de scolarité',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: periodicity,
                decoration: const InputDecoration(labelText: 'Périodicité'),
                items: const ['mensuelle', 'trimestrielle', 'annuelle', 'unique']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => periodicity = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, name.text.trim().isNotEmpty),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    final value = name.text;
    name.dispose();
    if (save != true) return;
    try {
      await ref.read(financeRepositoryProvider).addFeeCategory(
            name: value,
            periodicity: periodicity,
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

  Future<void> _edit(BuildContext context,WidgetRef ref,FeeCategoryItem item) async {
    final name=TextEditingController(text:item.name);String periodicity=item.periodicity;
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:const Text('Modifier la rubrique'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Nom *')),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:periodicity,decoration:const InputDecoration(labelText:'Périodicité'),items:const ['mensuelle','trimestrielle','annuelle','unique'].map((p)=>DropdownMenuItem(value:p,child:Text(p))).toList(),onChanged:(v){if(v!=null)setD(()=>periodicity=v);})]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(c,name.text.trim().isNotEmpty),child:const Text('Enregistrer'))])));
    final n=name.text.trim();name.dispose();if(ok!=true)return;await ref.read(financeRepositoryProvider).updateFeeCategory(feeId:item.id,name:n,periodicity:periodicity);ref.invalidate(feeCategoriesProvider);ref.invalidate(feeGridProvider);ref.invalidate(auditEntriesProvider);
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
          '« ${item.name} » ne sera plus utilisée pour les prochaines générations d’échéances. '
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
