
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/pdf_output_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/report_repository.dart';
import '../../services/billing_pdf_service.dart';
import '../../services/document_identity.dart';
import '../../services/document_number_service.dart';

/// Un parcours documentaire unique : recherche, situation de l'élève,
/// avis des sommes à payer et facture annuelle consolidée.
class BillingDocumentsScreen extends ConsumerStatefulWidget {
  const BillingDocumentsScreen({super.key, required this.filter});
  final ReportFilter filter;

  @override
  ConsumerState<BillingDocumentsScreen> createState() =>
      _BillingDocumentsScreenState();
}

class _BillingDocumentsScreenState
    extends ConsumerState<BillingDocumentsScreen> {
  final _search = TextEditingController();
  Future<List<Map<String, Object?>>>? _future;
  String? _workingStudent;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _future = ref.read(reportRepositoryProvider).billingDues(
      filter: widget.filter,
    );
    if (mounted) setState(() {});
  }

  Future<void> _generate(String dueId, String studentId, {
    required bool invoice,
  }) async {
    if (_workingStudent != null) return;
    setState(() => _workingStudent = studentId);
    try {
      // Relire avant toute génération : ne jamais imprimer l'ancien aperçu.
      final repository = ref.read(reportRepositoryProvider);
      final detail = await repository.billingDetail(dueId);
      final all = await repository.studentBillingDues(dueId);
      final lines = invoice ? all : all.where((row) =>
          ((row['balance'] as num?)?.toInt() ?? 0) > 0).toList();
      if (lines.isEmpty) {
        throw StateError('Aucune échéance restant à payer pour cet élève.');
      }

      final establishment = await ref.read(establishmentProvider.future);
      final rawIdentity = await DocumentIdentity.fromEstablishment(establishment);
      final selectedYear = '${detail['school_year_label'] ?? ''}';
      final identity = selectedYear.isEmpty ? rawIdentity
          : rawIdentity.forSchoolYear(selectedYear);
      final type = invoice ? 'FAC' : 'ECH';
      // Une émission = une référence propre. Ne jamais remplacer l'empreinte
      // d'une facture historique par celle d'une situation plus récente.
      final uniqueEmission = '${dueId}_${DateTime.now().microsecondsSinceEpoch}';
      final registry = DocumentNumberService();
      final reference = await registry.getOrCreate(
        type: type, entityId: uniqueEmission,
      );
      final bytes = await BillingPdfService().build(
        data: detail,
        invoice: invoice,
        reference: reference,
        identity: identity,
        lines: lines,
      );
      await registry.recordFingerprint(reference: reference, bytes: bytes);
      final fileName = invoice ? 'Facture_scolaire_$reference.pdf'
          : 'Avis_echeance_$reference.pdf';
      final result = await outputPdf(bytes, fileName: fileName);
      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${invoice ? 'Facture' : 'Avis'} généré : $reference'),
        ));
      }
      _reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _workingStudent = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avis et factures scolaires'),
        actions: [
          IconButton(
            tooltip: 'Actualiser les montants',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Rechercher un élève, une famille ou un matricule',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  setState(() {});
                },
              ),
            ),
          ),
        ),
        Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Erreur de chargement : ${snapshot.error}'),
                TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ]),
            );
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final grouped = <String, List<Map<String, Object?>>>{};
            for (final due in snapshot.data!) {
              grouped.putIfAbsent('${due['student_id']}', () => []).add(due);
            }
            final query = _search.text.trim().toLowerCase();
            final students = grouped.entries.where((entry) {
              if (query.isEmpty) return true;
              final row = entry.value.first;
              return [
                row['student'], row['registration_number'], row['family'],
                row['classroom'], row['cycle'],
              ].join(' ').toLowerCase().contains(query);
            }).toList();
            final outstanding = students.fold<int>(0, (sum, entry) =>
                sum + entry.value.fold<int>(0, (n, row) =>
                    n + ((row['balance'] as num?)?.toInt() ?? 0)));
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(child: Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(spacing: 18, runSpacing: 6, children: [
                    Text('${students.length} élève(s)',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Reste à recouvrer : ${formatXaf(outstanding)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Text('Avis = sommes impayées · Facture = année complète'),
                  ]),
                ),
              )),
              if (students.isEmpty)
                const SliverFillRemaining(hasScrollBody: false,
                  child: Center(child: Text('Aucune échéance à afficher.')))
              else
                SliverList.builder(
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final entry = students[index];
                    final rows = entry.value;
                    final student = rows.first;
                    final remainder = rows.fold<int>(0, (sum, row) =>
                      sum + ((row['balance'] as num?)?.toInt() ?? 0));
                    final working = _workingStudent == entry.key;
                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                      child: ExpansionTile(
                        title: Text('${student['student']}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          '${student['registration_number']} · '
                          '${student['cycle']} / ${student['classroom']}'
                          ' · Reste : ${formatXaf(remainder)}',
                        ),
                        children: [
                          for (final row in rows)
                            ListTile(
                              dense: true,
                              title: Text('${row['fee']} · ${row['period_key']}'),
                              subtitle: Text(
                                'Dû : ${formatXaf((row['amount_due'] as num?) ?? 0)}'
                                ' · Payé : ${formatXaf((row['amount_paid'] as num?) ?? 0)}',
                              ),
                              trailing: Text(formatXaf(
                                  (row['balance'] as num?) ?? 0)),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              OutlinedButton.icon(
                                onPressed: (_workingStudent != null ||
                                    remainder <= 0)
                                    ? null : () => _generate(
                                        student['due_id'] as String, entry.key,
                                        invoice: false),
                                icon: const Icon(Icons.notifications_outlined),
                                label: const Text('Avis global PDF'),
                              ),
                              FilledButton.icon(
                                onPressed: _workingStudent != null ? null
                                  : () => _generate(
                                      student['due_id'] as String, entry.key,
                                      invoice: true),
                                icon: working
                                    ? const SizedBox(width: 16, height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.receipt_long_outlined),
                                label: const Text('Facture consolidée PDF'),
                              ),
                            ]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ]);
          },
        )),
      ]),
    );
  }
}
