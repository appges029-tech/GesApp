import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/finance_full.dart';
import 'billing_calendar_screen.dart';

/// Une échéance future est une obligation programmée, pas un retard.
class DuesScreen extends ConsumerWidget {
  const DuesScreen({super.key});

  DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Widget _section(String title, List<DueItem> dues, {bool emphasize = false}) {
    if (dues.isEmpty) return const SizedBox.shrink();
    final total = dues.fold<int>(0, (sum, d) => sum + d.balance);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        child: Text(title + ' · ' + formatXaf(total),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
      ...dues.map((due) => Card(child: ListTile(
        leading: Icon(emphasize ? Icons.warning_amber_rounded
          : Icons.calendar_today_outlined),
        title: Text(due.studentName),
        subtitle: Text(due.feeName + ' · ' + due.periodKey +
          (due.dueDate == null ? '' :
           ' · limite ' + due.dueDate!.day.toString().padLeft(2, '0') + '/' +
            due.dueDate!.month.toString().padLeft(2, '0') + '/' +
            due.dueDate!.year.toString())),
        trailing: Text(formatXaf(due.balance),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      ))),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(unpaidDuesProvider);
    final body = state.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_available_outlined, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        'Aucune échéance non réglée',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Si un élève devrait avoir une dette, vérifiez la rubrique, '
                        'le tarif de son cycle ou de sa classe, puis les dates '
                        'limites du calendrier de facturation. '
                        'Une rubrique sans calendrier complet ne crée pas '
                        'd’échéance fictive.',
                        textAlign: TextAlign.center,
                      ),
                      if (!OperatorSession.isReadOnly) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BillingCalendarScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Vérifier le calendrier'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final past = <DueItem>[];
          final todayDues = <DueItem>[];
          final upcoming = <DueItem>[];
          final undated = <DueItem>[];
          for (final item in items) {
            final due = item.dueDate;
            if (due == null) {
              undated.add(item);
            } else if (_day(due).isBefore(today)) {
              past.add(item);
            } else if (_day(due).isAtSameMomentAs(today)) {
              todayDues.add(item);
            } else {
              upcoming.add(item);
            }
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Card(child: Padding(padding: EdgeInsets.all(14),
              child: Text('Seules les échéances dont la date limite est '
                'dépassée constituent des retards. Les mensualités futures '
                'restent visibles dans le calendrier sans être comptées '
                'comme des retards.'))),
            _section('En retard', past, emphasize: true),
            _section('À régler aujourd’hui', todayDues),
            _section('Échéances futures', upcoming),
            _section('À vérifier : sans date limite', undated),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : ' + error.toString())),
      );
    if (WindowsUi.isDesktop(context)) {
      return WindowsPageScaffold(
        title: 'Échéanciers et impayés',
        subtitle: 'Retards, échéances actuelles et obligations futures',
        body: body,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Échéanciers et impayés')),
      body: body,
    );
  }
}
