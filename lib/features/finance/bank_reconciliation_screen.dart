import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';

class BankReconciliationScreen extends ConsumerStatefulWidget {
  const BankReconciliationScreen({super.key});

  @override
  ConsumerState<BankReconciliationScreen> createState() =>
      _BankReconciliationScreenState();
}

class _BankReconciliationScreenState
    extends ConsumerState<BankReconciliationScreen> {
  int _refresh = 0;

  Future<void> _create() async {
    final repo = ref.read(accountingRepositoryProvider);
    final accounts = (await repo.cashAccounts())
        .where((a) => a['type'] == 'bank' || a['type'] == 'mobile')
        .toList();
    if (!mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configurez au moins un compte banque ou Mobile Money.'),
      ));
      return;
    }

    var account = '${accounts.first['id']}';
    final balanceController = TextEditingController();
    var start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    var end = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nouveau rapprochement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: account,
                isExpanded: true,
                items: accounts
                    .map((a) => DropdownMenuItem(
                          value: '${a['id']}',
                          child: Text('${a['name']}'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => account = value);
                },
                decoration: const InputDecoration(labelText: 'Compte'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Solde du relevé'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Période'),
                subtitle: Text(
                  '${start.day}/${start.month}/${start.year} — ${end.day}/${end.month}/${end.year}',
                ),
                onTap: () async {
                  final range = await showDateRangePicker(
                    context: dialogContext,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDateRange: DateTimeRange(start: start, end: end),
                  );
                  if (range != null) {
                    setDialogState(() {
                      start = range.start;
                      end = range.end;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await repo.createReconciliation(
          cashAccountId: account,
          start: start,
          end: end,
          statementBalance: int.tryParse(balanceController.text) ?? 0,
        );
        if (mounted) setState(() => _refresh++);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  Future<void> _open(Map<String, Object?> reconciliation) async {
    final repo = ref.read(accountingRepositoryProvider);
    var items = await repo.reconciliationItems('${reconciliation['id']}');
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Rapprochement · ${reconciliation['account_name']}'),
          content: ResponsiveDialogContent(
            maxWidth: 760,
            child: SizedBox(
            height: MediaQuery.sizeOf(dialogContext).height < 650 ? 360 : 500,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final entryDate = '${item['entry_date']}'.split('T').first;
                      return CheckboxListTile(
                        value: item['cleared'] == 1,
                        onChanged: reconciliation['status'] == 'completed'
                            ? null
                            : (value) async {
                                await repo.setReconciled(
                                  '${item['id']}',
                                  value ?? false,
                                );
                                items = await repo.reconciliationItems(
                                  '${reconciliation['id']}',
                                );
                                setDialogState(() {});
                              },
                        title: Text(
                          '${item['reference']} · ${item['description']}',
                        ),
                        subtitle: Text(
                          '$entryDate · Débit ${formatXaf(item['debit'] as num)} · Crédit ${formatXaf(item['credit'] as num)}',
                        ),
                      );
                    },
                  ),
                ),
                Text(
                  'Solde relevé ${formatXaf(reconciliation['statement_balance'] as num)} · '
                  'Solde comptable ${formatXaf(reconciliation['book_balance'] as num)} · '
                  'Écart ${formatXaf(reconciliation['difference'] as num)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
            if (reconciliation['status'] != 'completed')
              FilledButton(
                onPressed: () async {
                  try {
                    await repo.completeReconciliation('${reconciliation['id']}');
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) setState(() => _refresh++);
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                child: const Text('Valider'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Rapprochements'),
          actions: [
            IconButton(
              onPressed: _create,
              icon: const Icon(Icons.add),
              tooltip: 'Nouveau rapprochement',
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          key: ValueKey(_refresh),
          future: ref.read(accountingRepositoryProvider).reconciliations(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return const Center(child: Text('Aucun rapprochement bancaire.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (_, index) {
                final row = rows[index];
                final start = '${row['period_start']}'.split('T').first;
                final end = '${row['period_end']}'.split('T').first;
                return Card(
                  child: ListTile(
                    onTap: () => _open(row),
                    leading: Icon(
                      row['status'] == 'completed' ? Icons.verified : Icons.rule,
                    ),
                    title: Text(
                      '${row['account_name']} · ${row['status'] == 'completed' ? 'Validé' : 'Brouillon'}',
                    ),
                    subtitle: Text('$start → $end'),
                    trailing: Text(formatXaf(row['difference'] as num)),
                  ),
                );
              },
            );
          },
        ),
      );
}
