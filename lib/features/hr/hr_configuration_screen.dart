import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/hr.dart';

class HrConfigurationScreen extends ConsumerStatefulWidget {
  const HrConfigurationScreen({super.key});

  @override
  ConsumerState<HrConfigurationScreen> createState() => _HrConfigurationScreenState();
}

class _HrConfigurationScreenState extends ConsumerState<HrConfigurationScreen> {
  int _refresh = 0;

  Future<void> _editDepartment([HrDepartment? department]) async {
    final name = TextEditingController(text: department?.name ?? '');
    final description = TextEditingController(text: department?.description ?? '');
    var active = department?.active ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(department == null ? 'Nouveau service' : 'Modifier le service'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
              const SizedBox(height: 8),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).saveDepartment(
            id: department?.id,
            name: name.text,
            description: description.text,
            active: active,
          );
      if (mounted) setState(() => _refresh++);
    }
    name.dispose();
    description.dispose();
  }

  Future<void> _editPosition([HrPosition? position]) async {
    final departments = await ref.read(hrRepositoryProvider).departments(activeOnly: false);
    if (!mounted) return;
    final name = TextEditingController(text: position?.name ?? '');
    final description = TextEditingController(text: position?.description ?? '');
    String? departmentId = position?.departmentId;
    var active = position?.active ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(position == null ? 'Nouveau poste' : 'Modifier le poste'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: departmentId,
                decoration: const InputDecoration(labelText: 'Service'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
                  ...departments.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name))),
                ],
                onChanged: (value) => setDialogState(() => departmentId = value),
              ),
              const SizedBox(height: 8),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).savePosition(
            id: position?.id,
            name: name.text,
            departmentId: departmentId,
            description: description.text,
            active: active,
          );
      if (mounted) setState(() => _refresh++);
    }
    name.dispose();
    description.dispose();
  }

  Future<void> _editComponent([Map<String, Object?>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final value = TextEditingController(text: item?['value']?.toString() ?? '0');
    var kind = item?['kind']?.toString() ?? 'earning';
    var calculation = item?['calculation_type']?.toString() ?? 'fixed';
    var active = (item?['active'] as int? ?? 1) == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(item == null ? 'Élément salarial' : 'Modifier l’élément'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'earning', child: Text('Gain / prime')),
                  DropdownMenuItem(value: 'deduction', child: Text('Retenue')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => kind = v);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: calculation,
                decoration: const InputDecoration(labelText: 'Calcul'),
                items: const [
                  DropdownMenuItem(value: 'fixed', child: Text('Montant fixe')),
                  DropdownMenuItem(value: 'percentage', child: Text('Pourcentage du salaire de base')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => calculation = v);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: calculation == 'percentage' ? 'Valeur (%)' : 'Valeur (XAF)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                value: active,
                onChanged: (v) => setDialogState(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).saveSalaryComponent(
            id: item?['id']?.toString(),
            name: name.text,
            kind: kind,
            calculationType: calculation,
            value: int.tryParse(value.text) ?? 0,
            active: active,
          );
      if (mounted) setState(() => _refresh++);
    }
    name.dispose();
    value.dispose();
  }


  Future<void> _editLeaveType([Map<String, Object?>? item]) async {
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    var paid = (item?['paid'] as int? ?? 1) == 1;
    var requiresProof = (item?['requires_proof'] as int? ?? 0) == 1;
    var active = (item?['active'] as int? ?? 1) == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(item == null ? 'Type de congé / permission' : 'Modifier le type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rémunéré'),
                value: paid,
                onChanged: (value) => setDialogState(() => paid = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Justificatif obligatoire'),
                value: requiresProof,
                onChanged: (value) => setDialogState(() => requiresProof = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                value: active,
                onChanged: (value) => setDialogState(() => active = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).saveLeaveType(
            id: item?['id']?.toString(),
            name: name.text,
            paid: paid,
            requiresProof: requiresProof,
            active: active,
          );
      if (mounted) setState(() => _refresh++);
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration RH')),
      body: ListView(
        key: ValueKey(_refresh),
        padding: const EdgeInsets.all(16),
        children: [
          _Header(title: 'Services', onAdd: () => _editDepartment()),
          FutureBuilder<List<HrDepartment>>(
            future: ref.read(hrRepositoryProvider).departments(activeOnly: false),
            builder: (context, snapshot) => Card(
              child: Column(
                children: [
                  for (final item in snapshot.data ?? const <HrDepartment>[])
                    ListTile(
                      title: Text(item.name),
                      subtitle: Text(item.active ? 'Actif' : 'Désactivé'),
                      trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editDepartment(item)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Header(title: 'Postes', onAdd: () => _editPosition()),
          FutureBuilder<List<HrPosition>>(
            future: ref.read(hrRepositoryProvider).positions(activeOnly: false),
            builder: (context, snapshot) => Card(
              child: Column(
                children: [
                  for (final item in snapshot.data ?? const <HrPosition>[])
                    ListTile(
                      title: Text(item.name),
                      subtitle: Text('${item.departmentName ?? 'Sans service'} · ${item.active ? 'Actif' : 'Désactivé'}'),
                      trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editPosition(item)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Header(title: 'Congés & permissions', onAdd: () => _editLeaveType()),
          FutureBuilder<List<Map<String, Object?>>>(
            future: ref.read(hrRepositoryProvider).leaveTypes(activeOnly: false),
            builder: (context, snapshot) => Card(
              child: Column(
                children: [
                  for (final item in snapshot.data ?? const <Map<String, Object?>>[])
                    ListTile(
                      title: Text(item['name'].toString()),
                      subtitle: Text(
                        '${(item['paid'] as int? ?? 0) == 1 ? 'Rémunéré' : 'Non rémunéré'} · '
                        '${(item['requires_proof'] as int? ?? 0) == 1 ? 'justificatif requis' : 'sans justificatif obligatoire'} · '
                        '${(item['active'] as int? ?? 0) == 1 ? 'actif' : 'désactivé'}',
                      ),
                      trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editLeaveType(item)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Header(title: 'Éléments de salaire', onAdd: () => _editComponent()),
          FutureBuilder<List<Map<String, Object?>>>(
            future: ref.read(hrRepositoryProvider).salaryComponents(activeOnly: false),
            builder: (context, snapshot) => Card(
              child: Column(
                children: [
                  for (final item in snapshot.data ?? const <Map<String, Object?>>[])
                    ListTile(
                      title: Text(item['name'].toString()),
                      subtitle: Text(
                        '${item['kind'] == 'earning' ? 'Gain' : 'Retenue'} · '
                        '${item['calculation_type'] == 'percentage' ? '${item['value']} %' : '${item['value']} XAF'}',
                      ),
                      trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editComponent(item)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
          FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Ajouter')),
        ],
      );
}
