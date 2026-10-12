import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import 'package:pdf/pdf.dart';
import '../../core/platform/pdf_output_service.dart';
import '../../services/document_identity.dart';
import '../../services/document_number_service.dart';
import '../../services/excel_export_service.dart';
import '../../services/report_pdf_service.dart';

class SupplierAccountingScreen extends ConsumerStatefulWidget {
  const SupplierAccountingScreen({super.key});

  @override
  ConsumerState<SupplierAccountingScreen> createState() =>
      _SupplierAccountingScreenState();
}

class _SupplierAccountingScreenState
    extends ConsumerState<SupplierAccountingScreen> {
  int _refresh = 0;
  bool _exporting = false;

  Future<void> _exportSupplier({required bool pdf}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final invoices = await ref.read(accountingRepositoryProvider).supplierInvoices();
      if (invoices.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune facture fournisseur à exporter.')));
        return;
      }
      const headers = ['Facture', 'Fournisseur', 'Date', 'Échéance',
        'Compte', 'Montant', 'Payé', 'Reste', 'Statut'];
      final rows = <List<String>>[];
      var total = 0, totalPaid = 0;
      for (final invoice in invoices) {
        final amount = (invoice['amount'] as num?)?.toInt() ?? 0;
        final paid = (invoice['amount_paid'] as num?)?.toInt() ?? 0;
        total += amount; totalPaid += paid;
        rows.add([
          '${invoice['invoice_number'] ?? ''}',
          '${invoice['supplier_name'] ?? ''}',
          '${invoice['invoice_date'] ?? ''}'.split('T').first,
          '${invoice['due_date'] ?? '—'}'.split('T').first,
          '${invoice['expense_account_name'] ?? ''}',
          formatXaf(amount), formatXaf(paid), formatXaf(amount - paid),
          '${invoice['status'] ?? ''}',
        ]);
      }
      rows.add(['TOTAL GÉNÉRAL', '', '', '', '',
        formatXaf(total), formatXaf(totalPaid),
        formatXaf(total - totalPaid), '']);
      if (pdf) {
        final establishment = await ref.read(establishmentProvider.future);
        final identity = await DocumentIdentity.fromEstablishment(establishment);
        final registry = DocumentNumberService();
        final reference = await registry.getOrCreate(
          type: 'FOU', entityId: 'situation:${DateTime.now().microsecondsSinceEpoch}');
        final bytes = await ReportPdfService().table(
          title: 'État des factures fournisseurs', headers: headers, rows: rows,
          identity: identity, reference: reference, pageFormat: PdfPageFormat.a4.landscape);
        await registry.recordFingerprint(reference: reference, bytes: bytes);
        await outputPdf(bytes, fileName: 'Fournisseurs_$reference.pdf');
      } else {
        await ExcelExportService().export(
          fileName: 'Etat_factures_fournisseurs', headers: headers, rows: rows);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pdf ? 'État fournisseurs PDF généré.'
            : 'État fournisseurs Excel généré.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export fournisseurs impossible : $error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }


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
              onPressed: _exporting ? null : () => _exportSupplier(pdf: true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'État fournisseurs PDF',
            ),
            IconButton(
              onPressed: _exporting ? null : () => _exportSupplier(pdf: false),
              icon: const Icon(Icons.table_view_outlined),
              tooltip: 'État fournisseurs Excel',
            ),
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
