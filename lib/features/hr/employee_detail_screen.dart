import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/platform/download_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/stored_image.dart';
import '../../data/models/hr.dart';
import '../../services/hr_document_service.dart';
import 'employee_form_screen.dart';

class EmployeeDetailScreen extends ConsumerStatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId});
  final String employeeId;

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  int _refresh = 0;

  Future<void> _changePhoto(EmployeeItem employee) async {
    final path = await HrDocumentService().pickAndStore(employee.id, folder: 'photos', allowedExtensions: const ['jpg','jpeg','png','webp']);
    if (path != null) {
      await ref.read(hrRepositoryProvider).updateEmployeePhoto(employee.id, path);
      if (mounted) setState(() => _refresh++);
    }
  }

  Future<void> _addAssignment(EmployeeItem employee) async {
    final positions = await ref.read(hrRepositoryProvider).positions();
    final years = await ref.read(settingsRepositoryProvider).schoolYears();
    if (!mounted || positions.isEmpty) return;
    var positionId = positions.first.id;
    String? schoolYearId;
    for (final year in years) {
      if (year.isActive) {
        schoolYearId = year.id;
        break;
      }
    }
    var start = DateTime.now();
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nouvelle affectation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: positionId,
                decoration: const InputDecoration(labelText: 'Poste'),
                items: positions
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.name}${p.departmentName == null ? '' : ' · ${p.departmentName}'}'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => positionId = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: schoolYearId,
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Non liée à une année')),
                  ...years.map((y) => DropdownMenuItem<String?>(value: y.id, child: Text(y.label))),
                ],
                onChanged: (value) => setDialogState(() => schoolYearId = value),
              ),
              ListTile(
                title: const Text('Prise d’effet'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: dialogContext,
                    initialDate: start,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) setDialogState(() => start = selected);
                },
              ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Observation')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Affecter')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).addAssignment(
            employeeId: employee.id,
            positionId: positionId,
            schoolYearId: schoolYearId,
            startDate: start,
            notes: note.text,
          );
      if (mounted) setState(() => _refresh++);
    }
    note.dispose();
  }

  Future<void> _addContract(EmployeeItem employee) async {
    final positions = await ref.read(hrRepositoryProvider).positions();
    if (!mounted) return;
    var type = 'CDI';
    String? positionId = positions.isEmpty ? null : positions.first.id;
    var start = DateTime.now();
    DateTime? end;
    final salary = TextEditingController();
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nouveau contrat'),
          content: ResponsiveDialogContent(maxWidth: 500, child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const ['CDI', 'CDD', 'Vacataire', 'Prestataire', 'Stage', 'Autre']
                        .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (positions.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: positionId,
                      decoration: const InputDecoration(labelText: 'Poste'),
                      items: positions.map((p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.name))).toList(),
                      onChanged: (value) => setDialogState(() => positionId = value),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: salary,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Salaire de base XAF'),
                  ),
                  ListTile(
                    title: const Text('Début'),
                    subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: dialogContext,
                        initialDate: start,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (selected != null) setDialogState(() => start = selected);
                    },
                  ),
                  ListTile(
                    title: const Text('Fin'),
                    subtitle: Text(end == null ? 'Sans date de fin' : DateFormat('dd/MM/yyyy').format(end!)),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: dialogContext,
                        initialDate: end ?? start.add(const Duration(days: 365)),
                        firstDate: start,
                        lastDate: DateTime(2100),
                      );
                      if (selected != null) setDialogState(() => end = selected);
                    },
                  ),
                  TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final documentPath = await HrDocumentService().pickAndStore(employee.id, folder: 'contracts');
      await ref.read(hrRepositoryProvider).addContract(
            employeeId: employee.id,
            contractType: type,
            startDate: start,
            endDate: end,
            baseSalary: int.tryParse(salary.text.replaceAll(' ', '')) ?? 0,
            positionId: positionId,
            documentPath: documentPath,
            notes: notes.text,
          );
      if (mounted) setState(() => _refresh++);
    }
    salary.dispose();
    notes.dispose();
  }

  Future<void> _addSalaryComponent(EmployeeItem employee) async {
    final components = await ref.read(hrRepositoryProvider).salaryComponents();
    if (!mounted || components.isEmpty) return;
    var componentId = components.first['id'].toString();
    final value = TextEditingController(text: components.first['value'].toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Élément de salaire'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: componentId,
                decoration: const InputDecoration(labelText: 'Élément'),
                items: components.map((item) => DropdownMenuItem(value: item['id'].toString(), child: Text(item['name'].toString()))).toList(),
                onChanged: (selected) {
                  if (selected == null) return;
                  final item = components.firstWhere((candidate) => candidate['id'].toString() == selected);
                  setDialogState(() => componentId = selected);
                  value.text = item['value'].toString();
                },
              ),
              const SizedBox(height: 10),
              TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valeur appliquée')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).assignSalaryComponent(
            employeeId: employee.id,
            componentId: componentId,
            value: int.tryParse(value.text) ?? 0,
          );
      if (mounted) setState(() => _refresh++);
    }
    value.dispose();
  }

  Future<void> _addDocument(EmployeeItem employee) async {
    final type = TextEditingController();
    final number = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajouter un document RH'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: type, decoration: const InputDecoration(labelText: 'Type de document *')),
            const SizedBox(height: 10),
            TextField(controller: number, decoration: const InputDecoration(labelText: 'Numéro (facultatif)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Choisir le fichier')),
        ],
      ),
    );
    if (confirmed == true && type.text.trim().isNotEmpty) {
      final path = await HrDocumentService().pickAndStore(employee.id);
      if (path != null) {
        await ref.read(hrRepositoryProvider).addEmployeeDocument(
              employeeId: employee.id,
              documentType: type.text,
              filePath: path,
              documentNumber: number.text,
            );
        if (mounted) setState(() => _refresh++);
      }
    }
    type.dispose();
    number.dispose();
  }

  Future<void> _openDocument(Map<String, Object?> document) async {
    final path = document['file_path']?.toString() ?? '';
    final bytes = await HrDocumentService().readBytes(path);
    if (bytes == null || bytes.isEmpty) return;
    final isPdf = bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
    await downloadBytes(
      bytes: bytes,
      fileName: 'RH_${document['document_type']}_${document['id']}.${isPdf ? 'pdf' : 'jpg'}',
      mimeType: isPdf ? 'application/pdf' : 'image/jpeg',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmployeeItem?>(
      key: ValueKey(_refresh),
      future: ref.read(hrRepositoryProvider).employee(widget.employeeId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final employee = snapshot.data!;
        return Scaffold(
          appBar: AppBar(
            title: Text(employee.fullName),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Modifier',
                onPressed: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: employee)),
                  );
                  if (mounted) setState(() => _refresh++);
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if ((employee.photoPath ?? '').isNotEmpty) ...[
                            ClipOval(
                              child: StoredImage(
                                reference: employee.photoPath!,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: Text(employee.fullName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                          IconButton(tooltip: 'Photo', onPressed: () => _changePhoto(employee), icon: const Icon(Icons.photo_camera_outlined)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${employee.employeeNumber} · ${employee.status.toUpperCase()}'),
                      const Divider(),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (employee.positionName != null) Chip(avatar: const Icon(Icons.badge_outlined, size: 18), label: Text(employee.positionName!)),
                          if (employee.departmentName != null) Chip(avatar: const Icon(Icons.apartment, size: 18), label: Text(employee.departmentName!)),
                          if (employee.phone != null) Chip(label: Text(employee.phone!)),
                          Chip(label: Text('Entrée ${DateFormat('dd/MM/yyyy').format(employee.hireDate)}')),
                        ],
                      ),
                      if ((employee.emergencyContactName ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Urgence : ${employee.emergencyContactName} · ${employee.emergencyContactPhone ?? ''}'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Affectations',
                action: 'Ajouter',
                onAction: () => _addAssignment(employee),
                child: FutureBuilder<List<EmployeeAssignment>>(
                  future: ref.read(hrRepositoryProvider).assignments(employee.id),
                  builder: (context, data) => Column(
                    children: [
                      for (final item in data.data ?? const <EmployeeAssignment>[])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.work_outline),
                          title: Text(item.positionName),
                          subtitle: Text('${item.departmentName ?? ''} · depuis ${DateFormat('dd/MM/yyyy').format(item.startDate)}${item.endDate == null ? '' : ' → ${DateFormat('dd/MM/yyyy').format(item.endDate!)}'}'),
                        ),
                    ],
                  ),
                ),
              ),
              _Section(
                title: 'Contrats',
                action: 'Ajouter',
                onAction: () => _addContract(employee),
                child: FutureBuilder<List<EmployeeContract>>(
                  future: ref.read(hrRepositoryProvider).contracts(employee.id),
                  builder: (context, data) => Column(
                    children: [
                      for (final item in data.data ?? const <EmployeeContract>[])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined),
                          title: Text('${item.contractType} · ${formatXaf(item.baseSalary)}'),
                          subtitle: Text('${DateFormat('dd/MM/yyyy').format(item.startDate)}${item.endDate == null ? ' · sans échéance' : ' → ${DateFormat('dd/MM/yyyy').format(item.endDate!)}'}'),
                        ),
                    ],
                  ),
                ),
              ),
              _Section(
                title: 'Éléments de salaire',
                action: 'Ajouter',
                onAction: () => _addSalaryComponent(employee),
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: ref.read(hrRepositoryProvider).employeeSalaryComponents(employee.id),
                  builder: (context, data) => Column(
                    children: [
                      for (final item in data.data ?? const <Map<String, Object?>>[])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(item['kind'] == 'deduction' ? Icons.remove_circle_outline : Icons.add_circle_outline),
                          title: Text(item['name'].toString()),
                          subtitle: Text('${item['kind'] == 'deduction' ? 'Retenue' : 'Gain'} · ${item['value']}'),
                        ),
                    ],
                  ),
                ),
              ),
              _Section(
                title: 'Documents RH',
                action: 'Ajouter',
                onAction: () => _addDocument(employee),
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: ref.read(hrRepositoryProvider).employeeDocuments(employee.id),
                  builder: (context, data) => Column(
                    children: [
                      for (final document in data.data ?? const <Map<String, Object?>>[])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.attach_file),
                          title: Text(document['document_type'].toString()),
                          subtitle: Text(document['document_number']?.toString() ?? ''),
                          onTap: () => _openDocument(document),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final path = document['file_path']?.toString() ?? '';
                              await ref.read(hrRepositoryProvider).deleteEmployeeDocument(document['id'].toString());
                              if (path.isNotEmpty) await HrDocumentService().delete(path);
                              if (mounted) setState(() => _refresh++);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _Section(
                title: 'Avances sur salaire',
                child: FutureBuilder<List<SalaryAdvanceItem>>(
                  future: ref.read(hrRepositoryProvider).advances(employeeId: employee.id),
                  builder: (context, data) => Column(
                    children: [
                      for (final advance in data.data ?? const <SalaryAdvanceItem>[])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(formatXaf(advance.amount)),
                          subtitle: Text('Solde : ${formatXaf(advance.balance)} · ${advance.status}'),
                        ),
                    ],
                  ),
                ),
              ),
              _Section(
                title: 'Historique des statuts',
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: ref.read(hrRepositoryProvider).employeeStatusHistory(employee.id),
                  builder: (context, data) => Column(
                    children: [
                      for (final item in data.data ?? const <Map<String, Object?>>[])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history),
                          title: Text('${item['old_status'] ?? 'Création'} → ${item['new_status']}'),
                          subtitle: Text(
                            '${DateFormat('dd/MM/yyyy').format(DateTime.parse(item['effective_at'].toString()))} · ${item['reason'] ?? ''}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action, this.onAction});
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                if (action != null) TextButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(action!)),
              ],
            ),
            child,
          ],
        ),
      ),
    );
  }
}
