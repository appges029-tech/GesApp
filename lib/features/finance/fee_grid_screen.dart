import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';

class FeeGridScreen extends ConsumerWidget {
  const FeeGridScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final fees = await ref.read(feeCategoriesProvider.future);
    if (fees.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d\'abord une rubrique de paiement.')));
      }
      return;
    }
    final cycles = await ref.read(cyclesProvider.future);
    final classrooms = await ref.read(classroomsProvider.future);
    final establishment = await ref.read(establishmentProvider.future);

    String? feeId = fees.first.id;
    String target = 'cycle';
    String? cycleId = cycles.isNotEmpty ? cycles.first['id'] as String : null;
    String? classroomId = classrooms.isNotEmpty ? classrooms.first.id : null;
    final amount = TextEditingController();
    DateTime validFrom = establishment?.schoolYearStart ?? DateTime.now();

    if (!context.mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau tarif'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: feeId,
                  decoration: const InputDecoration(labelText: 'Rubrique'),
                  items: fees.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                  onChanged: (value) => setState(() => feeId = value),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cycle', label: Text('Par cycle')),
                    ButtonSegment(value: 'classroom', label: Text('Par classe')),
                  ],
                  selected: {target},
                  onSelectionChanged: (value) => setState(() => target = value.first),
                ),
                const SizedBox(height: 10),
                if (target == 'cycle')
                  cycles.isEmpty
                      ? const Text('Aucun cycle configuré.')
                      : DropdownButtonFormField<String>(
                          initialValue: cycleId,
                          decoration: const InputDecoration(labelText: 'Cycle'),
                          items: cycles.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String))).toList(),
                          onChanged: (value) => setState(() => cycleId = value),
                        )
                else
                  classrooms.isEmpty
                      ? const Text('Aucune classe configurée.')
                      : DropdownButtonFormField<String>(
                          initialValue: classroomId,
                          decoration: const InputDecoration(labelText: 'Classe'),
                          items: classrooms.map((c) => DropdownMenuItem(value: c.id, child: Text(c.label))).toList(),
                          onChanged: (value) => setState(() => classroomId = value),
                        ),
                const SizedBox(height: 10),
                TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant (FCFA)')),
                const SizedBox(height: 8),
                const Text('Si les dates limites de cette rubrique sont déjà configurées, le tarif complétera automatiquement les échéanciers des élèves concernés. Les anciens paiements resteront inchangés.'),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Valable à partir du ${validFrom.day.toString().padLeft(2, '0')}/${validFrom.month.toString().padLeft(2, '0')}/${validFrom.year}'),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: validFrom, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (picked != null) setState(() => validFrom = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final valid = feeId != null && int.tryParse(amount.text.replaceAll(RegExp(r'\D'), '')) != null && (target == 'cycle' ? cycleId != null : classroomId != null);
                Navigator.pop(context, valid);
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    final parsedAmount = int.tryParse(amount.text.replaceAll(RegExp(r'\D'), ''));
    amount.dispose();
    if (created != true || parsedAmount == null) return;
    try {
      await ref.read(financeRepositoryProvider).addFeeGrid(
            feeId: feeId!,
            cycleId: target == 'cycle' ? cycleId : null,
            classroomId: target == 'classroom' ? classroomId : null,
            amount: parsedAmount,
            validFrom: validFrom,
          );
      ref.invalidate(feeGridProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tarif impossible : $error')),
        );
      }
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
