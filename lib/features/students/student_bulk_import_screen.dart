import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/cloud/supabase_bootstrap.dart';
import '../../core/session/operator_session.dart';
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


  Future<void> _importFromSupabase() async {
    if (_loading) return;
    final organizationId = OperatorSession.organizationId;
    if (!OperatorSession.isManager ||
        organizationId == null ||
        !SupabaseBootstrap.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connectez-vous comme Gestionnaire avec Internet.')),
        );
      }
      return;
    }
    setState(() {
      _loading = true;
      _file = null;
      _preview = null;
      _result = null;
    });
    try {
      // Seul le gestionnaire du tenant autorisé par RLS peut voir ce jeu.
      final cloudRows = await SupabaseBootstrap.client
          .from('tenant_demo_seed_students')
          .select('seed_code,first_name,last_name,classroom,cycle,gender,birth_date,birth_place,guardian_name,guardian_phone,family_name,nationality,address,origin_school')
          .eq('organization_id', organizationId)
          .order('seed_code');
      if (cloudRows.isEmpty) {
        throw StateError('Aucun jeu de démonstration Supabase pour cet établissement.');
      }
      final settings = ref.read(settingsRepositoryProvider);
      final students = ref.read(studentRepositoryProvider);
      final activeYear = await settings.activeSchoolYear();
      if (activeYear != null &&
          (activeYear.startDate.year != 2026 || activeYear.endDate.year != 2027)) {
        throw StateError('Activez d’abord l’année scolaire 2026–2027 dans Réglages.');
      }
      final proposedRows = <StudentImportRow>[];
      final expectedClasses = <String, String>{};
      for (var i = 0; i < cloudRows.length; i++) {
        final data = cloudRows[i];
        final name = data['classroom']?.toString().trim() ?? '';
        final cycle = data['cycle']?.toString().trim() ?? '';
        if (name.isEmpty || cycle.isEmpty ||
            (data['last_name']?.toString().trim().isEmpty ?? true) ||
            (data['first_name']?.toString().trim().isEmpty ?? true)) {
          throw StateError('Ligne Supabase ${i + 1} incomplète.');
        }
        final key = name.toLowerCase();
        if (expectedClasses.containsKey(key) && expectedClasses[key] != cycle) {
          throw StateError('La classe $name est rattachée à plusieurs cycles.');
        }
        expectedClasses[key] = cycle;
        proposedRows.add(StudentImportRow(
          line: i + 2,
          firstName: data['first_name'].toString(),
          lastName: data['last_name'].toString(),
          classroom: name,
          gender: data['gender']?.toString(),
          birthDate: DateTime.tryParse(data['birth_date']?.toString() ?? ''),
          birthPlace: data['birth_place']?.toString(),
          guardianName: data['guardian_name']?.toString(),
          guardianPhone: data['guardian_phone']?.toString(),
          familyName: data['family_name']?.toString(),
          nationality: data['nationality']?.toString(),
          address: data['address']?.toString(),
          originSchool: data['origin_school']?.toString(),
        ));
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Importer le jeu de démonstration Supabase ?'),
          content: Text(
            '${proposedRows.length} élèves fictifs seront proposés pour cet établissement. '
            'Les cycles et classes manquants seront créés, sans supprimer les élèves existants. '
            'Les doublons détectés seront ignorés. Cette opération écrit dans la base locale '
            'du Gestionnaire et devra ensuite être synchronisée.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Importer')),
          ],
        ),
      );
      if (confirmed != true) return;
      if (activeYear == null) {
        await settings.createSchoolYear(
          label: '2026-2027',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2027, 6, 30, 23, 59, 59),
          activate: true,
        );
      }
      final cycleRows = await settings.cycles();
      final cycleIds = <String, String>{
        for (final row in cycleRows)
          (row['name'] as String).trim().toLowerCase(): row['id'] as String,
      };
      for (final name in expectedClasses.values.toSet()) {
        if (!cycleIds.containsKey(name.toLowerCase())) {
          cycleIds[name.toLowerCase()] =
              await settings.addCycle(name: name);
        }
      }
      final classes = await students.classrooms();
      final classNames = <String, String>{
        for (final item in classes)
          item.name.trim().toLowerCase(): item.cycleName.trim().toLowerCase(),
      };
      for (final entry in expectedClasses.entries) {
        final expectedCycle = entry.value.toLowerCase();
        final existingCycle = classNames[entry.key];
        if (existingCycle != null && existingCycle != expectedCycle) {
          throw StateError('La classe ${entry.key} existe dans un autre cycle. Corrigez-la dans Réglages.');
        }
        if (existingCycle == null) {
          await settings.addClassroom(
            cycleId: cycleIds[expectedCycle]!,
            name: proposedRows.firstWhere(
              (row) => row.classroom.toLowerCase() == entry.key,
            ).classroom,
            capacity: 50,
          );
        }
      }
      final preview = await students.previewBulkImport(proposedRows);
      if (preview.errors.any((e) => e.contains('capacité'))) {
        throw StateError('Certaines classes ont une capacité insuffisante. Augmentez leur capacité puis relancez.');
      }
      if (preview.valid == 0) {
        if (mounted) {
          setState(() {
            _result = StudentBulkImportResult(
              imported: 0,
              skipped: preview.skipped,
              errors: preview.errors,
            );
          });
        }
        return;
      }
      final imported = await students.bulkImport(proposedRows);
      ref.invalidate(studentsProvider);
      ref.invalidate(classroomsProvider);
      ref.invalidate(allClassroomsProvider);
      ref.invalidate(cyclesProvider);
      ref.invalidate(familiesProvider);
      if (mounted) {
        setState(() {
          _result = imported;
          _preview = null;
          _file = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            '${imported.imported} élève(s) fictif(s) importé(s) depuis Supabase. '
            'Synchronisez maintenant les données de l’établissement.',
          )),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import Supabase impossible : $error')),
        );
      }
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
                const SizedBox(height: 8),
                if (OperatorSession.isManager && OperatorSession.organizationId != null)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _importFromSupabase,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Importer les données fictives depuis Supabase'),
                  ),
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
