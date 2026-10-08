import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../data/models/hr.dart';
import '../../services/hr_document_service.dart';

class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  int _refresh = 0;
  String? _filter;

  Future<void> _create() async {
    final employees = await ref.read(hrRepositoryProvider).employees(status: 'active', limit: 500);
    final types = await ref.read(hrRepositoryProvider).leaveTypes();
    if (!mounted || employees.isEmpty || types.isEmpty) return;

    String employeeId = employees.first.id;
    String leaveTypeId = types.first['id'].toString();
    DateTime start = DateTime.now();
    DateTime end = DateTime.now();
    final reasonController = TextEditingController();

    final result = await showDialog<_LeaveDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Demande de congé / permission'),
            content: ResponsiveDialogContent(maxWidth: 520, child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: employeeId,
                      decoration: const InputDecoration(labelText: 'Employé'),
                      items: employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.fullName))).toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => employeeId = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: leaveTypeId,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: types.map((t) => DropdownMenuItem(value: t['id'].toString(), child: Text(t['name'].toString()))).toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => leaveTypeId = value);
                      },
                    ),
                    ListTile(
                      title: const Text('Début'),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: dialogContext,
                          initialDate: start,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) setDialogState(() => start = selected);
                      },
                    ),
                    ListTile(
                      title: const Text('Fin'),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(end)),
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: dialogContext,
                          initialDate: end.isBefore(start) ? start : end,
                          firstDate: start,
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) setDialogState(() => end = selected);
                      },
                    ),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Motif'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _LeaveDraft(employeeId: employeeId, leaveTypeId: leaveTypeId, start: start, end: end),
                ),
                child: const Text('Soumettre'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final selectedType = types.firstWhere((t) => t['id'].toString() == result.leaveTypeId);
      String? proofPath;
      if ((selectedType['requires_proof'] as int? ?? 0) == 1) {
        proofPath = await HrDocumentService().pickAndStore(result.employeeId, folder: 'leave_proofs');
        if (proofPath == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Un justificatif est requis pour ce type de congé.')),
            );
          }
          reasonController.dispose();
          return;
        }
      }
      try {
        await ref.read(hrRepositoryProvider).requestLeave(
              employeeId: result.employeeId,
              leaveTypeId: result.leaveTypeId,
              startDate: result.start,
              endDate: result.end,
              reason: reasonController.text,
              proofPath: proofPath,
            );
        if (mounted) setState(() => _refresh++);
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    reasonController.dispose();
  }

  Future<void> _decide(LeaveRequestItem request, bool approve) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approuver la demande' : 'Refuser la demande'),
        content: TextField(
          controller: noteController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observation'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(hrRepositoryProvider).decideLeave(request.id, approve: approve, note: noteController.text);
      if (mounted) setState(() => _refresh++);
    }
    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Congés & permissions'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => setState(() => _filter = value == 'all' ? null : value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Toutes')),
              PopupMenuItem(value: 'pending', child: Text('En attente')),
              PopupMenuItem(value: 'approved', child: Text('Approuvées')),
              PopupMenuItem(value: 'rejected', child: Text('Refusées')),
            ],
          ),
        ],
      ),
      floatingActionButton: OperatorSession.isReadOnly ? null : FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Demande'),
      ),
      body: FutureBuilder<List<LeaveRequestItem>>(
        key: ValueKey('$_refresh-$_filter'),
        future: ref.read(hrRepositoryProvider).leaveRequests(status: _filter),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('Aucune demande.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final request = rows[index];
              final period = '${DateFormat('dd/MM').format(request.startDate)} → ${DateFormat('dd/MM/yyyy').format(request.endDate)}';
              final reason = (request.reason ?? '').trim();
              return Card(
                child: ListTile(
                  title: Text(request.employeeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${request.leaveTypeName} · $period · ${request.days} j\nStatut : ${request.status}${reason.isEmpty ? '' : '\n$reason'}'),
                  isThreeLine: true,
                  trailing: request.status == 'pending' && !OperatorSession.isReadOnly
                      ? PopupMenuButton<String>(
                          onSelected: (value) => _decide(request, value == 'approve'),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'approve', child: Text('Approuver')),
                            PopupMenuItem(value: 'reject', child: Text('Refuser')),
                          ],
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LeaveDraft {
  const _LeaveDraft({required this.employeeId, required this.leaveTypeId, required this.start, required this.end});
  final String employeeId;
  final String leaveTypeId;
  final DateTime start;
  final DateTime end;
}
