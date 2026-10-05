import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/family.dart';
import '../finance/payment_form_screen.dart';

class FamilyDetailScreen extends ConsumerWidget {
  const FamilyDetailScreen({super.key, required this.family});
  final FamilyItem family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(familyMembersProvider(family.id));
    final balance = ref.watch(familyBalanceProvider(family.id));
    return Scaffold(
      appBar: AppBar(title: Text(family.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentFormScreen())),
        icon: const Icon(Icons.add_card),
        label: const Text('Encaisser'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).copyWith(bottom: 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: balance.when(
                data: (b) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Situation financière de la famille', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    _row('Attendu', formatXaf(b.expected)),
                    _row('Encaissé', formatXaf(b.paid)),
                    _row('Solde restant', formatXaf(b.outstanding), bold: true),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Élèves de la famille', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          members.when(
            data: (items) => items.isEmpty
                ? const Padding(padding: EdgeInsets.all(12), child: Text('Aucun élève rattaché. Rattachez un élève à cette famille depuis sa fiche d\'inscription.'))
                : Column(
                    children: items
                        .map((m) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: Text(m.fullName),
                                subtitle: Text(m.classroomName),
                                trailing: Chip(label: Text(m.status)),
                              ),
                            ))
                        .toList(),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ],
        ),
      );
}
