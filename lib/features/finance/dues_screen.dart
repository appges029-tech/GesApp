import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/finance_full.dart';

enum _DueView { overdue, today, upcoming, undated, all }

/// Suivi par périmètre scolaire : même source de données que les exports.
class DuesScreen extends ConsumerStatefulWidget {
  const DuesScreen({super.key});

  @override
  ConsumerState<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends ConsumerState<DuesScreen> {
  final _search = TextEditingController();
  String? _yearId, _cycleId, _classroomId;
  _DueView _view = _DueView.overdue;
  Future<List<Map<String, Object?>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
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
                        'Aucune période impayée',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Si un élève devrait avoir une dette, vérifiez la rubrique, '
                        'le tarif de son cycle ou de sa classe et '
                        'son inscription dans l’année scolaire active. '
                        'Les périodes sont générées automatiquement.',
                        textAlign: TextAlign.center,
                      ),

                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_DueView>(
              showSelectedIcon: false,
              multiSelectionEnabled: false,
              selected: {_view},
              onSelectionChanged: (selected) => setState(() => _view = selected.first),
              segments: [
                for (final view in _DueView.values)
                  ButtonSegment(value: view, label: Text(_label(view))),
              ],
            ),
          ),
        ]),
      )),
      if (!hasYear)
        const Expanded(child: Center(
          child: Text('Sélectionnez ou activez une année scolaire '
              'pour consulter les impayés.'),
        ))
      else
        Expanded(child: FutureBuilder<List<Map<String, Object?>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Chargement impossible : ${snapshot.error}'),
                TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ]),
            );
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
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
            _section('Périodes à venir', upcoming),
            _section('Périodes sans date limite', undated),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erreur : ' + error.toString())),
      );
    if (WindowsUi.isDesktop(context)) {
      return WindowsPageScaffold(
        title: 'Suivi des impayés',
        subtitle: 'Retards, échéances actuelles et obligations futures',
        body: body,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi des impayés')),
      body: body,
    );
  }
}
