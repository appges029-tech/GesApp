import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';

class SupplierAccountingScreen extends ConsumerStatefulWidget {
  const SupplierAccountingScreen({super.key});

  @override
  ConsumerState<SupplierAccountingScreen> createState() =>
      _SupplierAccountingScreenState();
}

class _SupplierAccountingScreenState
    extends ConsumerState<SupplierAccountingScreen> {
  int _refresh = 0;

  Future<void> _newInvoice() async {
    final repo = ref.read(accountingRepositoryProvider);
    final accounts = await repo.expenseAccounts();
    if (!mounted) return;

    final numberController = TextEditingController();
    final supplierController = TextEditingController();
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    String? accountCode =
        accounts.isEmpty ? null : '${accounts.first['code']}';
    var invoiceDate = DateTime.now();
    var dueDate = DateTime.now().add(const Duration(days: 30));

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Facture fournisseur'),
          content: ResponsiveDialogContent(maxWidth: 520, child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: numberController,
                    decoration: const InputDecoration(labelText: 'N° facture'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: supplierController,
                    decoration: const InputDecoration(labelText: 'Fournisseur'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Montant XAF'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: accountCode,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Compte de charge'),
                    items: accounts
                        .map((account) => DropdownMenuItem(
                              value: '${account['code']}',
                              child: Text(
                                '${account['code']} · ${account['name']}',
                              ),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => accountCode = value),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date facture'),
                    subtitle: Text(
                      '${invoiceDate.day}/${invoiceDate.month}/${invoiceDate.year}',
                    ),
                    onTap: () async {
                      final value = await showDatePicker(
                        context: dialogContext,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: invoiceDate,
                      );
                      if (value != null) {
                        setDialogState(() => invoiceDate = value);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Échéance'),
                    subtitle:
                        Text('${dueDate.day}/${dueDate.month}/${dueDate.year}'),
                    onTap: () async {
                      final value = await showDatePicker(
                        context: dialogContext,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate,
                      );
                      if (value != null) {
                        setDialogState(() => dueDate = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && accountCode != null) {
      try {
        await repo.addSupplierInvoice(
          invoiceNumber: numberController.text,
          supplierName: supplierController.text,
          invoiceDate: invoiceDate,
          dueDate: dueDate,
          description: descriptionController.text,
          expenseAccountCode: accountCode!,
          amount: int.tryParse(amountController.text) ?? 0,
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

  Future<void> _pay(Map<String, Object?> invoice) async {
    final repo = ref.read(accountingRepositoryProvider);
    final cashAccounts = await repo.cashAccounts();
    if (!mounted || cashAccounts.isEmpty) return;

    final remaining = (invoice['amount'] as num).toInt() -
        (invoice['amount_paid'] as num).toInt();
    final amountController = TextEditingController(text: '$remaining');
    final referenceController = TextEditingController();
    var cashAccountId = '${cashAccounts.first['id']}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Régler ${invoice['invoice_number']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: cashAccountId,
                isExpanded: true,
                items: cashAccounts
                    .map((account) => DropdownMenuItem(
                          value: '${account['id']}',
                          child: Text('${account['name']}'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => cashAccountId = value);
                  }
                },
                decoration:
                    const InputDecoration(labelText: 'Compte de paiement'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(labelText: 'Référence'),
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
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await repo.paySupplierInvoice(
          invoiceId: '${invoice['id']}',
          cashAccountId: cashAccountId,
          amount: int.tryParse(amountController.text) ?? 0,
          paidAt: DateTime.now(),
          reference: referenceController.text,
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Fournisseurs & dettes'),
          actions: [
            IconButton(
              onPressed: _newInvoice,
              icon: const Icon(Icons.add),
              tooltip: 'Nouvelle facture',
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          key: ValueKey(_refresh),
          future: ref.read(accountingRepositoryProvider).supplierInvoices(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return const Center(child: Text('Aucune facture fournisseur.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final row = rows[index];
                final remaining = (row['amount'] as num).toInt() -
                    (row['amount_paid'] as num).toInt();
                return Card(
                  child: ListTile(
                    title: Text(
                      '${row['invoice_number']} · ${row['supplier_name']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${row['description']}\n'
                      'Total ${formatXaf(row['amount'] as num)} · '
                      'Payé ${formatXaf(row['amount_paid'] as num)} · '
                      'Solde ${formatXaf(remaining)}',
                    ),
                    isThreeLine: true,
                    trailing: remaining > 0
                        ? FilledButton(
                            onPressed: () => _pay(row),
                            child: const Text('Régler'),
                          )
                        : const Icon(Icons.check_circle_outline),
                  ),
                );
              },
            );
          },
        ),
      );
}
