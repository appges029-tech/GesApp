import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../services/student_bulk_import_service.dart';

class StudentBulkImportScreen extends ConsumerStatefulWidget {
  const StudentBulkImportScreen({super.key});

  @override
  ConsumerState<StudentBulkImportScreen> createState() => _StudentBulkImportScreenState();
}

class _StudentBulkImportScreenState extends ConsumerState<StudentBulkImportScreen> {
  final _service = StudentBulkImportService();
  StudentImportFile? _file;
  StudentBulkImportResult? _result;
  StudentBulkImportPreview? _preview;
  bool _loading = false;

  Future<void> _pick() async {
    setState(() { _loading = true; _result = null; _preview = null; });
    try {
      final parsed = await _service.pickAndParse();
      if (parsed != null) { final preview=await ref.read(studentRepositoryProvider).previewBulkImport(parsed.rows); if(mounted)setState((){_file=parsed;_preview=preview;}); }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fichier invalide : $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    final file = _file;
    if (file == null || file.rows.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer les élèves ?'),
        content: Text('${_preview?.valid ?? 0} ligne(s) seront importées dans UNE transaction. ${_preview?.skipped ?? 0} ligne(s) seront ignorées. Si une erreur inattendue survient pendant l’écriture, toute la transaction sera annulée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Importer')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      final result = await ref.read(studentRepositoryProvider).bulkImport(file.rows);
      ref.invalidate(studentsProvider);
      ref.invalidate(classroomsProvider);
      ref.invalidate(familiesProvider);
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return Scaffold(
      appBar: AppBar(title: const Text('Import massif élèves')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('CSV / Excel (.xlsx)', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Colonnes obligatoires : nom, prénom, classe. Colonnes facultatives : sexe, date_naissance, lieu_naissance, responsable, telephone, famille, nationalite, adresse, ecole_origine.'),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _loading ? null : _pick, icon: const Icon(Icons.upload_file), label: const Text('Choisir un fichier')),
              ]),
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
          if (file != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(file.fileName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${_preview?.valid ?? 0} valide(s) sur ${file.rows.length} · ${_preview?.skipped ?? 0} ignorée(s)'),
                  if ((_preview?.errors.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Text('Analyse avant import : ${_preview!.errors.length} anomalie(s)', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                    ..._preview!.errors.take(15).map((e) => Text('• $e')),
                  ],
                  if (file.warnings.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('${file.warnings.length} avertissement(s)', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                    ...file.warnings.take(10).map((e) => Text('• $e')),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _loading || !(_preview?.canImport ?? false) ? null : _import, icon: const Icon(Icons.group_add), label: const Text('Lancer l’import')),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text('Aperçu', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ...file.rows.take(15).map((r) => ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${r.line}')),
              title: Text('${r.lastName} ${r.firstName}'),
              subtitle: Text('${r.classroom}${r.guardianName == null ? '' : ' · ${r.guardianName}'}'),
            )),
          ],
          if (_result != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Import terminé', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${_result!.imported} importé(s) · ${_result!.skipped} ignoré(s)'),
                  if (_result!.errors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._result!.errors.take(20).map((e) => Text('• $e')),
                  ],
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
