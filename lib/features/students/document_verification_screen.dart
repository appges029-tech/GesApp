import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';

class DocumentVerificationScreen extends ConsumerStatefulWidget {
  const DocumentVerificationScreen({super.key});

  @override
  ConsumerState<DocumentVerificationScreen> createState() => _DocumentVerificationScreenState();
}

class _DocumentVerificationScreenState extends ConsumerState<DocumentVerificationScreen> {
  final _code = TextEditingController();
  Map<String, Object?>? _result;
  bool _searched = false;
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final value = _code.text.trim();
    if (value.isEmpty) return;
    setState(() => _loading = true);
    try {
      final result = await ref.read(studentRepositoryProvider).verifyDocumentCode(value);
      if (!mounted) return;
      setState(() {
        _result = result;
        _searched = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final valid = result?['verification_status'] == 'valid';
    return Scaffold(
      appBar: AppBar(title: const Text('Vérifier un document scolaire')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Contrôle d’authenticité', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('Saisissez la référence DOC-… inscrite dans le dossier de l’élève. GesApp confirme si la pièce existe encore et si elle est valide.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Référence du document', prefixIcon: Icon(Icons.verified_outlined)),
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _loading ? null : _verify, icon: const Icon(Icons.search), label: const Text('Vérifier'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_searched && result == null)
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error), const SizedBox(width: 12), const Expanded(child: Text('Aucun document correspondant à cette référence.'))]))),
          if (result != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(valid ? Icons.verified_rounded : Icons.block_rounded, color: valid ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(valid ? 'Document valide' : 'Document invalidé', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  ]),
                  const Divider(height: 28),
                  _line('Référence', '${result['verification_code']}'),
                  _line('Type', '${result['document_type']}'),
                  _line('Élève', '${result['last_name']} ${result['first_name']}'),
                  _line('Matricule', '${result['registration_number'] ?? '—'}'),
                  _line('Classe', '${result['cycle_name']} · ${result['classroom_name']}'),
                  _line('Ajouté le', '${result['added_at']}'.split('T').first),
                  if (!valid && result['revoked_at'] != null) _line('Invalidé le', '${result['revoked_at']}'.split('T').first),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(value)),
        ]),
      );
}
