import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/repositories/report_repository.dart';
import 'finance_scope_filters.dart';
import 'payment_form_screen.dart';

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
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _future = ref.read(reportRepositoryProvider).unpaid(
      filter: ReportFilter(
        schoolYearId: _yearId,
        cycleId: _cycleId,
        classroomId: _classroomId,
      ),
    );
    if (mounted) setState(() {});
  }

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  _DueView _type(Map<String, Object?> row, DateTime today) {
    final due = _date(row['due_date']);
    if (due == null) return _DueView.undated;
    final day = DateTime(due.year, due.month, due.day);
    if (day.isBefore(today)) return _DueView.overdue;
    if (day.isAfter(today)) return _DueView.upcoming;
    return _DueView.today;
  }

  String _label(_DueView value) => switch (value) {
    _DueView.overdue => 'En retard',
    _DueView.today => 'À régler aujourd’hui',
    _DueView.upcoming => 'À venir',
    _DueView.undated => 'Sans date limite',
    _DueView.all => 'Toutes les échéances non soldées',
  };

  Future<void> _collect(Map<String, Object?> row) async {
    if (!OperatorSession.isManager) return;
    final years = await ref.read(schoolYearsProvider.future);
    final active = years.where((y) => y.isActive).firstOrNull;
    if (_yearId != null && _yearId != active?.id) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pour régler une ancienne échéance, '
            'utilisez le formulaire de paiement après avoir vérifié '
            'l’année scolaire concernée.')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => PaymentFormScreen(
        initialStudentId: row['student_id'] as String?,
        initialDueId: row['due_id'] as String?,
      ),
    ));
    ref.invalidate(unpaidDuesProvider);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(schoolYearsProvider);
    final active = years.valueOrNull?.where((y) => y.isActive).firstOrNull;
    final chosen = _yearId == null
        ? active : years.valueOrNull?.where((y) => y.id == _yearId).firstOrNull;
    final hasYear = chosen != null;
    final future = _future;

    final content = Column(children: [
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Filtrer les impayés',
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          FinanceScopeFilters(
            yearId: _yearId, cycleId: _cycleId,
            classroomId: _classroomId,
            onYear: (id) { _yearId = id; _cycleId = null; _classroomId = null; _reload(); },
            onCycle: (id) { _cycleId = id; _classroomId = null; _reload(); },
            onClassroom: (id) { _classroomId = id; _reload(); },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Élève, matricule, famille ou rubrique',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Effacer la recherche',
                icon: const Icon(Icons.clear),
                onPressed: () { _search.clear(); setState(() {}); },
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
            final text = _search.text.trim().toLowerCase();
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final filtered = snapshot.data!.where((row) {
              if (_view != _DueView.all && _type(row, today) != _view) return false;
              final haystack = [
                row['student'], row['registration_number'],
                row['family'], row['fee'], row['period_key'],
              ].map((x) => (x ?? '').toString().toLowerCase()).join(' ');
              return text.isEmpty || haystack.contains(text);
            }).toList(growable: false);
            final total = filtered.fold<int>(0,
              (sum, row) => sum + ((row['balance'] as num?)?.toInt() ?? 0));
            final students = filtered.map((r) => r['student_id']).toSet().length;
            return RefreshIndicator(
              onRefresh: () async { _reload(); await _future; },
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(child: Card(child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 16, runSpacing: 7, children: [
                    Text('Année : ${chosen.label}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${filtered.length} échéance(s)'),
                    Text('$students élève(s)'),
                    Text('Reste : ${formatXaf(total)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ))),
                if (filtered.isEmpty)
                  SliverFillRemaining(hasScrollBody: false,
                    child: Center(child: Text(
                      text.isEmpty ? 'Aucune échéance pour ce périmètre.'
                          : 'Aucun résultat pour cette recherche.')))
                else
                  SliverList.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final due = filtered[index];
                      final deadline = _date(due['due_date']);
                      final remaining = (due['balance'] as num?)?.toInt() ?? 0;
                      return Card(child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text('${due['student'] ?? 'Élève'} · ${formatXaf(remaining)}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          '${due['cycle'] ?? '—'} / ${due['classroom'] ?? '—'}'
                          ' · ${due['fee'] ?? '—'} · ${due['period_key'] ?? '—'}\n'
                          'Dû ${formatXaf((due['amount_due'] as num?) ?? 0)}'
                          ' · Payé ${formatXaf((due['amount_paid'] as num?) ?? 0)}'
                          ' · Échéance ${deadline == null ? 'non précisée' : '${deadline.day.toString().padLeft(2, '0')}/${deadline.month.toString().padLeft(2, '0')}/${deadline.year}'}',
                        ),
                        isThreeLine: true,
                        trailing: OperatorSession.isManager
                            ? IconButton(
                                tooltip: 'Encaisser pour cet élève',
                                onPressed: () => _collect(due),
                                icon: const Icon(Icons.add_card_outlined),
                              ) : null,
                      ));
                    },
                  ),
              ]),
            );
          },
        )),
    ]);

    return WindowsUi.isDesktop(context)
        ? WindowsPageScaffold(
            title: 'Gestion des impayés',
            subtitle: 'Année scolaire, cycle, classe et suivi des paiements',
            body: content)
        : Scaffold(
            appBar: AppBar(title: const Text('Gestion des impayés'),
              actions: [
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh),
                  tooltip: 'Actualiser'),
              ]),
            body: content);
  }
}
