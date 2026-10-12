import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/recovery.dart';
import 'finance_scope_filters.dart';

class RecoveryScreen extends ConsumerStatefulWidget {
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  final _search = TextEditingController();
  List<RecoveryCaseItem> _cases = const [];
  bool _loading = true;
  String? _schoolYearId, _cycleId, _classroomId;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await ref.read(recoveryRepositoryProvider).cases(
        search: _search.text,
        schoolYearId: _schoolYearId,
        cycleId: _cycleId,
        classroomId: _classroomId,
      );
      if (mounted) setState(() => _cases = rows);
    } catch (error) {
      if (mounted) setState(() {
        _error = '$error';
        _cases = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showHistory(RecoveryCaseItem item) async {
    final rows = await ref.read(recoveryRepositoryProvider).history(item.dueId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              ListTile(
                title: Text(item.studentName, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${item.feeName} · ${item.periodKey} · ${formatXaf(item.balance)} restant'),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('Aucune relance enregistrée.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final row = rows[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.history),
                              title: Text('${row.actionType}${row.channel == null ? '' : ' · ${row.channel}'}'),
                              subtitle: Text([
                                DateFormat('dd/MM/yyyy HH:mm').format(row.createdAt),
                                if ((row.outcome ?? '').isNotEmpty) 'Résultat : ${row.outcome}',
                                if (row.promiseAmount != null) 'Promesse : ${formatXaf(row.promiseAmount!)}${row.promiseDate == null ? '' : ' le ${DateFormat('dd/MM/yyyy').format(row.promiseDate!)}'}',
                                if (row.nextFollowUpAt != null) 'Prochaine relance : ${DateFormat('dd/MM/yyyy').format(row.nextFollowUpAt!)}',
                                if ((row.note ?? '').isNotEmpty) row.note!,
                              ].join('\n')),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addAction(RecoveryCaseItem item) async {
    final contact = TextEditingController(text: item.guardianName ?? '');
    final outcome = TextEditingController();
    final note = TextEditingController();
    final promiseAmount = TextEditingController();
    var actionType = 'Relance';
    var channel = 'Téléphone';
    DateTime? promiseDate;
    DateTime? nextFollowUp;

    Future<DateTime?> pick(BuildContext dialogContext, DateTime? initial) => showDatePicker(
          context: dialogContext,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 730)),
          initialDate: initial ?? DateTime.now(),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Nouvelle action de recouvrement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: actionType,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: const ['Relance', 'Promesse de paiement', 'Visite', 'Note'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setLocalState(() => actionType = v ?? actionType),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: channel,
                  decoration: const InputDecoration(labelText: 'Canal'),
                  items: const ['Téléphone', 'SMS', 'Email', 'Présentiel', 'Application'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setLocalState(() => channel = v ?? channel),
                ),
                const SizedBox(height: 12),
                TextField(controller: contact, decoration: const InputDecoration(labelText: 'Personne contactée')),
                const SizedBox(height: 12),
                TextField(controller: outcome, decoration: const InputDecoration(labelText: 'Résultat de la relance')),
                if (actionType == 'Promesse de paiement') ...[
                  const SizedBox(height: 12),
                  TextField(controller: promiseAmount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant promis')),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(promiseDate == null ? 'Date promise' : 'Date promise : ${DateFormat('dd/MM/yyyy').format(promiseDate!)}'),
                    trailing: const Icon(Icons.event_available_outlined),
                    onTap: () async {
                      final value = await pick(dialogContext, promiseDate);
                      if (value != null) setLocalState(() => promiseDate = value);
                    },
                  ),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(nextFollowUp == null ? 'Planifier une prochaine relance' : 'Prochaine relance : ${DateFormat('dd/MM/yyyy').format(nextFollowUp!)}'),
                  trailing: const Icon(Icons.notification_add_outlined),
                  onTap: () async {
                    final value = await pick(dialogContext, nextFollowUp);
                    if (value != null) setLocalState(() => nextFollowUp = value);
                  },
                ),
                TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Note')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    final amount = int.tryParse(promiseAmount.text.replaceAll(RegExp(r'\D'), ''));
    final contactValue = contact.text;
    final outcomeValue = outcome.text;
    final noteValue = note.text;
    contact.dispose();
    outcome.dispose();
    note.dispose();
    promiseAmount.dispose();
    if (ok != true) return;
    try {
      await ref.read(recoveryRepositoryProvider).addAction(
            dueId: item.dueId,
            actionType: actionType,
            channel: channel,
            contactName: contactValue,
            outcome: outcomeValue,
            promiseAmount: actionType == 'Promesse de paiement' ? amount : null,
            promiseDate: actionType == 'Promesse de paiement' ? promiseDate : null,
            nextFollowUpAt: nextFollowUp,
            note: noteValue,
          );
      ref.invalidate(auditEntriesProvider);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action de recouvrement enregistrée.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Color _severityColor(BuildContext context, int days) {
    final scheme = Theme.of(context).colorScheme;
    if (days >= 90) return scheme.errorContainer;
    if (days >= 30) return scheme.tertiaryContainer;
    return scheme.surfaceContainerHighest;
  }

  @override
  Widget build(BuildContext context) {
    final total = _cases.fold<int>(0, (sum, item) => sum + item.balance);
    return Scaffold(
      appBar: AppBar(title: const Text('Recouvrement')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: FinanceScopeFilters(
              yearId: _schoolYearId, cycleId: _cycleId,
              classroomId: _classroomId,
              onYear: (value) {
                _schoolYearId = value; _cycleId = null; _classroomId = null; _load();
              },
              onCycle: (value) {
                _cycleId = value; _classroomId = null; _load();
              },
              onClassroom: (value) {
                _classroomId = value; _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Rechercher élève, famille, parent ou téléphone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.arrow_forward)),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text('${_cases.length} échéance(s) en retard'),
                trailing: Text(formatXaf(total), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _cases.isEmpty
                        ? ListView(children: const [SizedBox(height: 120), Center(child: Text('Aucun impayé en retard.'))])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: _cases.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final item = _cases[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text('${item.studentName} · ${item.classroomName}', style: const TextStyle(fontWeight: FontWeight.w800))),
                                          Text(formatXaf(item.balance), style: const TextStyle(fontWeight: FontWeight.w800)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          Chip(backgroundColor: _severityColor(context, item.daysLate), label: Text('${item.daysLate} j de retard')),
                                          Chip(label: Text('${item.feeName} · ${item.periodKey}')),
                                        ],
                                      ),
                                      if ((item.guardianName ?? '').isNotEmpty || (item.guardianPhone ?? '').isNotEmpty)
                                        Text('Contact : ${item.guardianName ?? '—'} · ${item.guardianPhone ?? '—'}'),
                                      if (item.promiseAmount != null)
                                        Text('Promesse : ${formatXaf(item.promiseAmount!)}${item.promiseDate == null ? '' : ' le ${DateFormat('dd/MM/yyyy').format(item.promiseDate!)}'}'),
                                      if (item.nextFollowUpAt != null)
                                        Text('Prochaine relance : ${DateFormat('dd/MM/yyyy').format(item.nextFollowUpAt!)}'),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(onPressed: () => _showHistory(item), icon: const Icon(Icons.history), label: const Text('Historique')),
                                          const SizedBox(width: 8),
                                          if (!OperatorSession.isReadOnly) FilledButton.tonalIcon(onPressed: () => _addAction(item), icon: const Icon(Icons.add_ic_call_outlined), label: const Text('Relancer')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
