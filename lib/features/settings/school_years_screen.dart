import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../data/repositories/settings_repository.dart';

class SchoolYearsScreen extends ConsumerStatefulWidget {
  const SchoolYearsScreen({super.key});

  @override
  ConsumerState<SchoolYearsScreen> createState() => _SchoolYearsScreenState();
}

class _SchoolYearsScreenState extends ConsumerState<SchoolYearsScreen> {
  List<SchoolYearItem> _years = const [];
  bool _loading = true;

  Future<void> _load() async {
    final years = await ref.read(settingsRepositoryProvider).schoolYears();
    if (!mounted) return;
    setState(() {
      _years = years;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _create() async {
    final label = TextEditingController();
    var start = DateTime(DateTime.now().year, 9, 1);
    var end = DateTime(DateTime.now().year + 1, 7, 31);
    var activate = _years.isEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Nouvelle année scolaire'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: label, decoration: const InputDecoration(labelText: 'Libellé, ex. 2026-2027')),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Début'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final value = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: start);
                  if (value != null) setLocalState(() => start = value);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fin'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(end)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final value = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: end);
                  if (value != null) setLocalState(() => end = value);
                },
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Rendre active immédiatement'), value: activate, onChanged: (value) => setLocalState(() => activate = value)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(settingsRepositoryProvider).createSchoolYear(label: label.text, startDate: start, endDate: end, activate: activate);
      ref.invalidate(establishmentProvider);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _activate(SchoolYearItem year) async {
    if (year.isActive) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Activer ${year.label} ?'),
        content: const Text('Les nouvelles inscriptions et réinscriptions seront rattachées à cette année. Les années précédentes restent conservées dans l’historique.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Activer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(settingsRepositoryProvider).activateSchoolYear(year.id);
      ref.invalidate(establishmentProvider);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Années scolaires')),
      floatingActionButton: OperatorSession.isReadOnly ? null : FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nouvelle année')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _years.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Aucune année scolaire enregistrée. Configurez l’établissement ou créez une année.')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _years.map((year) => Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(year.isActive ? Icons.check_circle : Icons.calendar_month_outlined)),
                      title: Text(year.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${DateFormat('dd/MM/yyyy').format(year.startDate)} → ${DateFormat('dd/MM/yyyy').format(year.endDate)}${year.isActive ? '\nAnnée active' : ''}'),
                      isThreeLine: year.isActive,
                      trailing: year.isActive || OperatorSession.isReadOnly ? null : TextButton(onPressed: () => _activate(year), child: const Text('Activer')),
                    ),
                  )).toList(),
                ),
    );
  }
}
