import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';

/// Le périmètre est toujours explicite : année scolaire -> cycle -> classe.
/// Si aucune année n'est choisie, l'année configurée active est utilisée.
class FinanceScopeFilters extends ConsumerWidget {
  const FinanceScopeFilters({
    super.key,
    required this.yearId,
    required this.cycleId,
    required this.classroomId,
    required this.onYear,
    required this.onCycle,
    required this.onClassroom,
  });

  final String? yearId, cycleId, classroomId;
  final ValueChanged<String?> onYear, onCycle, onClassroom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final years = ref.watch(schoolYearsProvider);
    final cycles = ref.watch(cyclesProvider);
    final classes = ref.watch(allClassroomsProvider);
    final child = <Widget>[
      years.when(
        data: (items) {
          final active = items.where((y) => y.isActive).firstOrNull;
          final value = items.any((y) => y.id == yearId)
              ? yearId : active?.id;
          if (value == null) {
            return const ListTile(
              leading: Icon(Icons.warning_amber_rounded),
              title: Text('Aucune année scolaire active'),
              subtitle: Text('Activez une année dans les paramètres avant de suivre les impayés.'),
            );
          }
          return DropdownButtonFormField<String>(
            key: ValueKey('finance_year_$value'),
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Année scolaire', prefixIcon: Icon(Icons.event_outlined)),
            items: items.map((y) => DropdownMenuItem(
              value: y.id,
              child: Text('${y.label}${y.isActive ? " · en cours" : ""}',
                overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: onYear,
          );
        },
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Années indisponibles : $error'),
      ),
      cycles.when(
        data: (items) => DropdownButtonFormField<String>(
          key: ValueKey('finance_cycle_$cycleId'),
          initialValue: items.any((c) => c['id'] == cycleId) ? cycleId : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Cycle', prefixIcon: Icon(Icons.school_outlined)),
          hint: const Text('Tous les cycles'),
          items: [
            const DropdownMenuItem<String>(value: '', child: Text('Tous les cycles')),
            ...items.map((c) => DropdownMenuItem(
              value: c['id'] as String,
              child: Text(c['name'] as String, overflow: TextOverflow.ellipsis),
            )),
          ],
          onChanged: (id) => onCycle(id == '' ? null : id),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Cycles indisponibles : $error'),
      ),
      classes.when(
        data: (items) {
          final shown = cycleId == null ? items
              : items.where((c) => c.cycleId == cycleId).toList();
          return DropdownButtonFormField<String>(
            key: ValueKey('finance_class_${cycleId}_$classroomId'),
            initialValue: shown.any((c) => c.id == classroomId)
                ? classroomId : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Classe', prefixIcon: Icon(Icons.meeting_room_outlined)),
            hint: const Text('Toutes les classes'),
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('Toutes les classes')),
              ...shown.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text('${c.cycleName} · ${c.name}',
                    overflow: TextOverflow.ellipsis),
              )),
            ],
            onChanged: (id) => onClassroom(id == '' ? null : id),
          );
        },
        loading: () => const LinearProgressIndicator(),
        error: (error, _) => Text('Classes indisponibles : $error'),
      ),
    ];

    return LayoutBuilder(builder: (_, constraints) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final widget in child)
          SizedBox(
            width: constraints.maxWidth >= 900
                ? (constraints.maxWidth - 20) / 3
                : constraints.maxWidth >= 550
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth,
            child: widget,
          ),
      ],
    ));
  }
}
