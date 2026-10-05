import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';

class PackagesScreen extends ConsumerWidget {
  const PackagesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final students = await ref.read(studentsProvider.future);
    final families = await ref.read(familiesProvider.future);
    final fees = await ref.read(feeCategoriesProvider.future);
    final establishment = await ref.read(establishmentProvider.future);

    String type = 'individual';
    String? feeId = fees.isNotEmpty ? fees.first.id : null;
    String? studentId = students.isNotEmpty ? students.first.id : null;
    String? familyId = families.isNotEmpty ? families.first.id : null;
    final amount = TextEditingController();
    final reason = TextEditingController();
    DateTime validFrom = establishment?.schoolYearStart ?? DateTime.now();
    DateTime? validTo;

    if (!context.mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouveau forfait'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'individual', label: Text('Individuel')),
                    ButtonSegment(value: 'family', label: Text('Familial')),
                  ],
                  selected: {type},
                  onSelectionChanged: (value) => setState(() => type = value.first),
                ),
                const SizedBox(height: 10),
                fees.isEmpty
                    ? const Text('Créez d’abord une rubrique de paiement avant de définir un forfait.')
                    : DropdownButtonFormField<String>(
                        initialValue: feeId,
                        decoration: const InputDecoration(labelText: 'Rubrique concernée'),
                        items: fees.map((f) => DropdownMenuItem(value: f.id, child: Text('${f.name} · ${f.periodicity}'))).toList(),
                        onChanged: (value) => setState(() => feeId = value),
                      ),
                const SizedBox(height: 10),
                if (type == 'individual')
                  students.isEmpty
                      ? const Text('Aucun élève inscrit.')
                      : DropdownButtonFormField<String>(
                          initialValue: studentId,
                          decoration: const InputDecoration(labelText: 'Élève'),
                          items: students.map((s) => DropdownMenuItem(value: s.id, child: Text(s.fullName))).toList(),
                          onChanged: (value) => setState(() => studentId = value),
                        )
                else
                  families.isEmpty
                      ? const Text('Aucune famille enregistrée.')
                      : DropdownButtonFormField<String>(
                          initialValue: familyId,
                          decoration: const InputDecoration(labelText: 'Famille'),
                          items: families.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
                          onChanged: (value) => setState(() => familyId = value),
                        ),
                const SizedBox(height: 10),
                TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant du forfait (FCFA)')),
                const SizedBox(height: 10),
                TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motif (bourse, réduction fratrie…)')),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(validTo == null ? 'Aucune date de fin (illimité)' : 'Jusqu\'au ${validTo!.day.toString().padLeft(2, '0')}/${validTo!.month.toString().padLeft(2, '0')}/${validTo!.year}'),
                  trailing: const Icon(Icons.event_busy_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: validFrom, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (picked != null) setState(() => validTo = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final beneficiaryOk = type == 'individual' ? studentId != null : familyId != null;
                final valid = beneficiaryOk && feeId != null && (int.tryParse(amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0) > 0;
                Navigator.pop(context, valid);
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    final parsedAmount = int.tryParse(amount.text.replaceAll(RegExp(r'\D'), ''));
    final reasonValue = reason.text.trim();
    amount.dispose();
    reason.dispose();
    if (created != true || parsedAmount == null) return;
    try {
      await ref.read(financeRepositoryProvider).createPackage(
            type: type,
            feeId: feeId!,
            studentId: type == 'individual' ? studentId : null,
            familyId: type == 'family' ? familyId : null,
            amount: parsedAmount,
            reason: reasonValue.isEmpty ? null : reasonValue,
            validFrom: validFrom,
            validTo: validTo,
          );
      ref.invalidate(packagesProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Création impossible : $error')));
      }
    }
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref, String packageId, String beneficiary) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Désactiver le forfait ?'),
        content: Text('Le forfait de $beneficiary ne s’appliquera plus aux prochaines échéances. Les échéances déjà générées restent inchangées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Désactiver')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(financeRepositoryProvider).deactivatePackage(packageId);
      ref.invalidate(packagesProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Désactivation impossible : $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(packagesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Forfaits')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.add), label: const Text('Forfait')),
      body: a.when(
        data: (x) => x.isEmpty
            ? const Center(child: Text('Aucun forfait.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16).copyWith(bottom: 96),
                itemCount: x.length,
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: Text(x[i].beneficiary),
                    subtitle: Text('${x[i].type == 'family' ? 'Forfait familial' : 'Forfait individuel'} · ${x[i].feeName}${x[i].reason != null ? ' · ${x[i].reason}' : ''}${x[i].active ? '' : ' · Inactif'}'),
                    trailing: Text(formatXaf(x[i].amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onLongPress: x[i].active ? () => _deactivate(context, ref, x[i].id, x[i].beneficiary) : null,
                  ),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
