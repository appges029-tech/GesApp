import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../services/document_number_service.dart';

class ReceiptVerificationScreen extends ConsumerStatefulWidget {
  const ReceiptVerificationScreen({super.key});

  @override
  ConsumerState<ReceiptVerificationScreen> createState() => _ReceiptVerificationScreenState();
}

class _ReceiptVerificationScreenState extends ConsumerState<ReceiptVerificationScreen> {
  final _receiptController = TextEditingController();
  ReceiptVerificationResult? _result;
  Map<String, String>? _documentResult;
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _receiptController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final number = _receiptController.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez le numéro du reçu ou la référence du document.')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _searched = true;
      _result = null;
      _documentResult = null;
    });
    try {
      final result = await ref.read(financeRepositoryProvider).verifyReceipt(number);
      final documentResult = result == null ? await DocumentNumberService().referenceInfo(number) : null;
      if (!mounted) return;
      setState(() {
        _result = result;
        _documentResult = documentResult;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vérification impossible : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Vérifier un document')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Authentification locale d’un document',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Saisissez un numéro de reçu ou une référence documentaire GesApp. L’application vérifiera son enregistrement local et, lorsqu’elle existe, son empreinte SHA-256.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _receiptController,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              labelText: 'Numéro / référence',
              hintText: 'Ex. REC-2026-000123 ou FAC-2026-000001',
              prefixIcon: const Icon(Icons.receipt_long_outlined),
              suffixIcon: IconButton(
                tooltip: 'Effacer',
                onPressed: () {
                  _receiptController.clear();
                  setState(() {
                    _result = null;
                    _documentResult = null;
                    _searched = false;
                  });
                },
                icon: const Icon(Icons.clear),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _verify,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_outlined),
            label: const Text('Vérifier l’authenticité'),
          ),
          const SizedBox(height: 20),
          if (_searched && !_loading && result == null && _documentResult == null)
            _StatusCard(
              icon: Icons.cancel_outlined,
              title: 'Document introuvable',
              message: 'Aucun reçu ni document généré ne correspond à cette référence dans cette base GesApp.',
              color: Theme.of(context).colorScheme.error,
            ),
          if (_documentResult != null) ...[
            _StatusCard(
              icon: (_documentResult!['status'] ?? 'valid') == 'revoked' ? Icons.warning_amber_rounded : Icons.verified_rounded,
              title: (_documentResult!['status'] ?? 'valid') == 'revoked' ? 'Document révoqué' : 'Document GesApp enregistré',
              message: (_documentResult!['status'] ?? 'valid') == 'revoked' ? 'Cette référence existe, mais le document a été révoqué.' : 'Cette référence a été attribuée par le moteur documentaire local de GesApp.',
              color: (_documentResult!['status'] ?? 'valid') == 'revoked' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _row('Référence', _documentResult!['reference'] ?? ''),
                  _row('Type', _documentResult!['type'] ?? 'DOC'),
                  _row('Statut', (_documentResult!['status'] ?? 'valid') == 'revoked' ? 'Révoqué' : 'Valide'),
                  if ((_documentResult!['generated_by'] ?? '').isNotEmpty) _row('Généré par', _documentResult!['generated_by']!),
                  if ((_documentResult!['registered_at'] ?? '').isNotEmpty) _row('Enregistré le', _documentResult!['registered_at']!),
                  if ((_documentResult!['sha256'] ?? '').isNotEmpty) _row('Empreinte SHA-256', _documentResult!['sha256']!),
                ]),
              ),
            ),
          ],
          if (result != null) ...[
            _StatusCard(
              icon: result.isCancelled ? Icons.warning_amber_rounded : Icons.verified_rounded,
              title: result.isCancelled ? 'Reçu authentique mais annulé' : 'Reçu authentique',
              message: result.isCancelled
                  ? 'Ce numéro existe, mais le paiement a été annulé et ne doit plus être considéré comme valable.'
                  : 'Ce numéro correspond à un paiement enregistré dans GesApp.',
              color: result.isCancelled
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('N° reçu', result.receiptNumber),
                    _row('Bénéficiaire', result.beneficiaryName),
                    _row('Montant encaissé', formatXaf(result.amount)),
                    if (result.refundedAmount > 0) _row('Montant remboursé', formatXaf(result.refundedAmount)),
                    if (result.refundedAmount > 0) _row('Montant net', formatXaf(result.netAmount)),
                    _row('Mode de paiement', result.method),
                    _row('Date', DateFormat('dd/MM/yyyy HH:mm').format(result.paidAt)),
                    if (result.schoolYearLabel != null) _row('Année scolaire', result.schoolYearLabel!),
                    if (result.transactionReference?.trim().isNotEmpty == true)
                      _row('Référence transaction', result.transactionReference!),
                    if (result.payerPhone?.trim().isNotEmpty == true) _row('Téléphone payeur', result.payerPhone!),
                    if (result.isCancelled && result.cancelReason?.trim().isNotEmpty == true)
                      _row('Motif d’annulation', result.cancelReason!),
                    if (result.lines.isNotEmpty) ...[
                      const Divider(height: 26),
                      const Text('Affectation du paiement', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      ...result.lines.map(
                        (line) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(line.label)),
                              const SizedBox(width: 12),
                              Text(formatXaf(line.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.title, required this.message, required this.color});

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 17)),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
