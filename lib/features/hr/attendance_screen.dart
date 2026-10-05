import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/layout/responsive_layout.dart';
import '../../data/models/hr.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _date = DateTime.now();
  int _refresh = 0;

  void _reload() => setState(() => _refresh++);

  Future<void> _mark(EmployeeItem employee, String status) async {
    await ref.read(hrRepositoryProvider).setAttendance(
          employeeId: employee.id,
          date: _date,
          status: status,
        );
    if (mounted) _reload();
  }

  Future<void> _edit(EmployeeItem employee, AttendanceItem? current) async {
    var status = current?.status ?? 'present';
    final arrival = TextEditingController(text: current?.arrivalTime ?? '');
    final departure = TextEditingController(text: current?.departureTime ?? '');
    final lateMinutes = TextEditingController(text: '${current?.lateMinutes ?? 0}');
    final note = TextEditingController(text: current?.note ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(employee.fullName),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      DropdownMenuItem(value: 'present', child: Text('Présent')),
                      DropdownMenuItem(value: 'absent', child: Text('Absent')),
                      DropdownMenuItem(value: 'late', child: Text('Retard')),
                      DropdownMenuItem(value: 'permission', child: Text('Permission')),
                      DropdownMenuItem(value: 'leave', child: Text('Congé')),
                      DropdownMenuItem(value: 'mission', child: Text('Mission')),
                      DropdownMenuItem(value: 'sick', child: Text('Maladie')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => status = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  ResponsiveFormRow(
                    breakpoint: 480,
                    children: [
                      TextField(
                          controller: arrival,
                          decoration: const InputDecoration(
                            labelText: 'Heure d’arrivée',
                            hintText: '07:45',
                          ),
                      ),
                      TextField(
                          controller: departure,
                          decoration: const InputDecoration(
                            labelText: 'Heure de départ',
                            hintText: '16:00',
                          ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lateMinutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes de retard'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Observation'),
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

    try {
      if (confirmed == true) {
        await ref.read(hrRepositoryProvider).setAttendance(
              employeeId: employee.id,
              date: _date,
              status: status,
              arrivalTime: arrival.text.trim().isEmpty ? null : arrival.text.trim(),
              departureTime: departure.text.trim().isEmpty ? null : departure.text.trim(),
              lateMinutes: int.tryParse(lateMinutes.text.trim()) ?? 0,
              note: note.text.trim(),
            );
        if (mounted) _reload();
      }
    } finally {
      arrival.dispose();
      departure.dispose();
      lateMinutes.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Présences'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (selected != null) setState(() => _date = selected);
            },
          ),
        ],
      ),
      body: FutureBuilder<List<EmployeeItem>>(
        key: ValueKey('$_refresh-${_date.toIso8601String()}'),
        future: ref.read(hrRepositoryProvider).employees(status: 'active', limit: 500),
        builder: (context, employeeSnapshot) {
          if (!employeeSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<List<AttendanceItem>>(
            future: ref.read(hrRepositoryProvider).attendance(_date),
            builder: (context, attendanceSnapshot) {
              final attendanceByEmployee = {
                for (final item in attendanceSnapshot.data ?? const <AttendanceItem>[])
                  item.employeeId: item,
              };
              return ResponsiveContent(
                maxWidth: 1100,
                padding: ResponsiveLayout.pagePadding(context),
                child: ListView(
                children: [
                  Text(
                    DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(_date),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final employee in employeeSnapshot.data!)
                    Card(
                      child: ListTile(
                        title: Text(employee.fullName),
                        subtitle: Text(
                          '${employee.employeeNumber}${attendanceByEmployee[employee.id] == null ? '' : ' · ${_label(attendanceByEmployee[employee.id]!.status)}'}',
                        ),
                        onTap: () => _edit(employee, attendanceByEmployee[employee.id]),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Marquer rapidement',
                          onSelected: (value) => _mark(employee, value),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'present', child: Text('Présent')),
                            PopupMenuItem(value: 'absent', child: Text('Absent')),
                            PopupMenuItem(value: 'late', child: Text('Retard')),
                            PopupMenuItem(value: 'permission', child: Text('Permission')),
                            PopupMenuItem(value: 'leave', child: Text('Congé')),
                            PopupMenuItem(value: 'mission', child: Text('Mission')),
                            PopupMenuItem(value: 'sick', child: Text('Maladie')),
                          ],
                        ),
                      ),
                    ),
                ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _label(String status) => switch (status) {
        'present' => 'Présent',
        'absent' => 'Absent',
        'late' => 'Retard',
        'permission' => 'Permission',
        'leave' => 'Congé',
        'mission' => 'Mission',
        'sick' => 'Maladie',
        _ => status,
      };
}
