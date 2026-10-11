import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';

class FeeGridScreen extends ConsumerWidget {
  const FeeGridScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final fees = await ref.read(feeCategoriesProvider.future);
    if (fees.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d’abord une rubrique de paiement.')));
      return;
    }
    final cycles = await ref.read(cyclesProvider.future);
    final classrooms = await ref.read(classroomsProvider.future);
    final establishment = await ref.read(establishmentProvider.future);
    if (!context.mounted) return;

    String? feeId = fees.first.id;
    String target = 'cycle';
    String? cycleId = cycles.isEmpty ? null : cycles.first['id'] as String;
    String? classroomId = classrooms.isEmpty ? null : classrooms.first.id;
    String amount = '';
    String? error;
    DateTime validFrom = establishment?.schoolYearStart ?? DateTime.now();

    final data = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Nouveau tarif'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: feeId,
                  decoration: const InputDecoration(labelText: 'Rubrique'),
                  items: fees.map((fee) => DropdownMenuItem(
                    value: fee.id,
                    child: Text(fee.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (value) => refresh(() => feeId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Appliquer le tarif'),
                  items: const [
                    DropdownMenuItem(value: 'cycle', child: Text('À tout un cycle')),
                    DropdownMenuItem(value: 'classroom', child: Text('À une classe précise')),
                  ],
                  onChanged: (value) { if (value != null) refresh(() => target = value); },
                ),
                const SizedBox(height: 12),
                if (target == 'cycle')
                  cycles.isEmpty ? const Text('Aucun cycle configuré.') :
                  DropdownButtonFormField<String>(
                    key: const ValueKey('tariff_cycle'),
                    initialValue: cycleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Cycle'),
                    items: cycles.map((cycle) => DropdownMenuItem(
                      value: cycle['id'] as String,
                      child: Text((cycle['name'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => refresh(() => cycleId = value),
                  )
                else
                  classrooms.isEmpty ? const Text('Aucune classe configurée.') :
                  DropdownButtonFormField<String>(
                    key: const ValueKey('tariff_class'),
                    initialValue: classroomId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: classrooms.map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.label, maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) => refresh(() => classroomId = value),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Montant par période (FCFA)',
                    errorText: error,
                  ),
                  onChanged: (value) => amount = value,
                ),
                const SizedBox(height: 10),
                const Text('La périodicité de la rubrique détermine automatiquement '
                  'les mois ou trimestres à payer. Aucun échéancier manuel n’est requis.'),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Valable dès le ${validFrom.day.toString().padLeft(2, '0')}/'
                    '${validFrom.month.toString().padLeft(2, '0')}/${validFrom.year}'),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final chosen = await showDatePicker(
                      context: dialogContext,
                      initialDate: validFrom,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null && dialogContext.mounted) {
                      refresh(() => validFrom = chosen);
                    }
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final amountValue = int.tryParse(amount.replaceAll(RegExp(r'\D'), ''));
                if (amountValue == null || amountValue <= 0) {
                  refresh(() => error = 'Saisissez un montant supérieur à zéro.');
                  return;
                }
                if (feeId == null || (target == 'cycle' ? cycleId : classroomId) == null) {
                  refresh(() => error = 'Sélectionnez la rubrique et le cycle ou la classe.');
                  return;
                }
                Navigator.pop(dialogContext, {
                  'feeId': feeId!,
                  'cycleId': target == 'cycle' ? cycleId : null,
                  'classroomId': target == 'classroom' ? classroomId : null,
                  'amount': amountValue,
                  'validFrom': validFrom,
                });
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    if (data == null || !context.mounted) return;
    try {
      await ref.read(financeRepositoryProvider).addFeeGrid(
        feeId: data['feeId'] as String,
        cycleId: data['cycleId'] as String?,
        classroomId: data['classroomId'] as String?,
        amount: data['amount'] as int,
        validFrom: data['validFrom'] as DateTime,
      );
      ref.invalidate(feeGridProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tarif impossible : $error')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(feeGridProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Grille tarifaire'),actions:[IconButton(tooltip:'Historique des tarifs',icon:const Icon(Icons.history),onPressed:()async{final rows=await ref.read(financeRepositoryProvider).feeGridHistory();if(!context.mounted)return;Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('Historique des tarifs')),body:ListView.separated(padding:const EdgeInsets.all(16),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(_,i){final r=rows[i];return Card(child:ListTile(title:Text('${r['fee_name']} · ${r['target_name']}',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('Du ${('${r['valid_from']}').split('T').first}${r['valid_to']==null?' · actuel':' au ${('${r['valid_to']}').split('T').first}'}'),trailing:Text(formatXaf(r['amount'] as int),style:const TextStyle(fontWeight:FontWeight.bold))));}))));})]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.add), label: const Text('Tarif')),
      body: data.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('Aucun tarif configuré.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16).copyWith(bottom: 96),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final x = items[i];
                  return Card(child: ListTile(title: Text(x.feeName), subtitle: Text(x.targetName), trailing: Text(formatXaf(x.amount), style: const TextStyle(fontWeight: FontWeight.bold))));
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
