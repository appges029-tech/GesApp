import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/platform/download_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/sensitive_authorization_dialog.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/expense.dart';
import '../../services/expense_proof_service.dart';
import 'expense_form_screen.dart';
import 'recurring_expenses_screen.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String? _filter;
  final _query = TextEditingController();
  List<ExpenseItem> _items = const [];
  bool _loading = false, _hasMore = true;
  int _offset = 0;
  static const _page = 75;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _offset = 0;
      _items = const [];
      _hasMore = true;
    }
    if (!_hasMore) return;
    setState(() => _loading = true);
    final rows = await ref.read(expenseRepositoryProvider).list(
          approvalStatus: _filter,
          query: _query.text,
          limit: _page,
          offset: _offset,
        );
    if (mounted) {
      setState(() {
        _items = [..._items, ...rows];
        _offset += rows.length;
        _hasMore = rows.length == _page;
        _loading = false;
      });
    }
  }

  Future<String?> _askNote(String title, {bool required = false}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(labelText: required ? 'Motif *' : 'Note (facultative)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(x, !required || c.text.trim().isNotEmpty), child: const Text('Confirmer')),
        ],
      ),
    );
    final v = c.text.trim();
    c.dispose();
    return ok == true ? v : null;
  }

  Future<void> _approve(ExpenseItem item) async {
    final note = await _askNote('Approuver ${item.expenseNumber ?? 'la dépense'} ?');
    if (note == null) return;
    final authorization = await requestSensitiveAuthorization(
      context: context,
      repository: ref.read(securityRepositoryProvider),
      action: 'expense_approve_authorization',
      entityId: item.id,
    );
    if (authorization == null) return;
    await ref.read(expenseRepositoryProvider).approveExpense(expenseId: item.id, note: note);
    await _refresh();
  }

  Future<void> _reject(ExpenseItem item) async {
    final note = await _askNote('Rejeter cette dépense ?', required: true);
    if (note == null) return;
    await ref.read(expenseRepositoryProvider).rejectExpense(expenseId: item.id, reason: note);
    await _refresh();
  }

  Future<void> _resubmit(ExpenseItem item) async {
    final note = await _askNote('Resoumettre cette dépense ?');
    if (note == null) return;
    await ref.read(expenseRepositoryProvider).resubmitExpense(expenseId: item.id, note: note);
    await _refresh();
  }

  Future<void> _cancel(ExpenseItem item) async {
    final note = await _askNote('Annuler cette dépense approuvée ?', required: true);
    if (note == null) return;
    final authorization = await requestSensitiveAuthorization(
      context: context,
      repository: ref.read(securityRepositoryProvider),
      action: 'expense_cancel_authorization',
      entityId: item.id,
    );
    if (authorization == null) return;
    await ref.read(expenseRepositoryProvider).cancelExpense(expenseId: item.id, reason: note);
    await _refresh();
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(auditEntriesProvider);
    await _load(reset: true);
  }

  Future<void> _openProof(ExpenseItem item) async {
    final reference = item.proofPath;
    if (reference == null || reference.isEmpty) return;
    final bytes = await ExpenseProofService().readBytes(reference);
    if (bytes == null || bytes.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Justificatif introuvable.')));
      return;
    }
    final isPdf = bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;
    final isPng = bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final ext = isPdf ? 'pdf' : isPng ? 'png' : 'jpg';
    await downloadBytes(
      bytes: bytes,
      fileName: 'Justificatif_${item.expenseNumber ?? item.id}.$ext',
      mimeType: isPdf ? 'application/pdf' : isPng ? 'image/png' : 'image/jpeg',
    );
  }

  String _status(ExpenseItem item) => item.isPending ? 'En attente' : item.isRejected ? 'Rejetée' : 'Approuvée';

  Color _statusColor(BuildContext context, ExpenseItem item) => item.isPending
      ? Theme.of(context).colorScheme.tertiaryContainer
      : item.isRejected
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer;

  Future<void> _newExpense() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpenseFormScreen()));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = WindowsUi.isDesktop(context);
    final body = Column(
      children: [
        Padding(
          padding: desktop ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  onSubmitted: (_) => _load(reset: true),
                  decoration: InputDecoration(
                    labelText: 'Rechercher numéro, description, bénéficiaire ou référence',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(onPressed: () => _load(reset: true), icon: const Icon(Icons.arrow_forward)),
                  ),
                ),
              ),
              if (desktop) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: _filter ?? 'all',
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Toutes')),
                      DropdownMenuItem(value: 'pending', child: Text('En attente')),
                      DropdownMenuItem(value: 'approved', child: Text('Approuvées')),
                      DropdownMenuItem(value: 'rejected', child: Text('Rejetées')),
                    ],
                    onChanged: (value) {
                      setState(() => _filter = value == 'all' ? null : value);
                      _load(reset: true);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: desktop ? 14 : 4),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(child: Text('Aucune dépense pour ce filtre.'))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: desktop
                      ? _DesktopExpenseList(
                          items: _items,
                          loading: _loading,
                          hasMore: _hasMore,
                          onLoadMore: _load,
                          onProof: _openProof,
                          onApprove: _approve,
                          onReject: _reject,
                          onResubmit: _resubmit,
                          onCancel: _cancel,
                          statusLabel: _status,
                          statusColor: _statusColor,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16).copyWith(bottom: 96),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            if (index == _items.length) {
                              return Center(child: _loading ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()) : OutlinedButton(onPressed: _load, child: const Text('Charger plus')));
                            }
                            final item = _items[index];
                            return _ExpenseCard(
                              item: item,
                              status: _status(item),
                              statusColor: _statusColor(context, item),
                              onProof: () => _openProof(item),
                              onApprove: () => _approve(item),
                              onReject: () => _reject(item),
                              onResubmit: () => _resubmit(item),
                              onCancel: () => _cancel(item),
                            );
                          },
                        ),
                ),
        ),
        if (_loading && _items.isNotEmpty) const LinearProgressIndicator(),
      ],
    );

    return WindowsPageScaffold(
      title: 'Dépenses',
      subtitle: desktop ? '${_items.length} opération(s) chargée(s) · validation et justificatifs' : null,
      actions: [
        WindowsCommandButton(
          icon: Icons.repeat_rounded,
          label: 'Récurrentes',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecurringExpensesScreen())),
        ),
        if (!desktop)
          PopupMenuButton<String?>(
            tooltip: 'Filtrer',
            onSelected: (v) {
              setState(() => _filter = v == 'all' ? null : v);
              _load(reset: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Toutes')),
              PopupMenuItem(value: 'pending', child: Text('En attente')),
              PopupMenuItem(value: 'approved', child: Text('Approuvées')),
              PopupMenuItem(value: 'rejected', child: Text('Rejetées')),
            ],
          ),
        if (desktop && !OperatorSession.isReadOnly) WindowsCommandButton(icon: Icons.add, label: 'Nouvelle demande', primary: true, onPressed: _newExpense),
      ],
      floatingActionButton: desktop || OperatorSession.isReadOnly ? null : FloatingActionButton.extended(onPressed: _newExpense, icon: const Icon(Icons.add), label: const Text('Nouvelle demande')),
      body: body,
    );
  }
}

class _DesktopExpenseList extends StatelessWidget {
  const _DesktopExpenseList({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    required this.onProof,
    required this.onApprove,
    required this.onReject,
    required this.onResubmit,
    required this.onCancel,
    required this.statusLabel,
    required this.statusColor,
  });

  final List<ExpenseItem> items;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final ValueChanged<ExpenseItem> onProof;
  final ValueChanged<ExpenseItem> onApprove;
  final ValueChanged<ExpenseItem> onReject;
  final ValueChanged<ExpenseItem> onResubmit;
  final ValueChanged<ExpenseItem> onCancel;
  final String Function(ExpenseItem) statusLabel;
  final Color Function(BuildContext, ExpenseItem) statusColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return WindowsPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: scheme.surfaceContainerLow,
            child: const Row(children: [
              Expanded(flex: 2, child: _ExpenseHeader('N° / date')),
              Expanded(flex: 3, child: _ExpenseHeader('Catégorie / bénéficiaire')),
              Expanded(flex: 3, child: _ExpenseHeader('Description')),
              Expanded(flex: 2, child: _ExpenseHeader('Statut')),
              Expanded(flex: 2, child: _ExpenseHeader('Montant')),
              SizedBox(width: 46),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .55)),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(child: loading ? const CircularProgressIndicator() : OutlinedButton(onPressed: onLoadMore, child: const Text('Charger plus'))),
                  );
                }
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(children: [
                    Expanded(flex: 2, child: Text('${item.expenseNumber ?? '—'}\n${DateFormat('dd/MM/yyyy').format(item.spentAt)}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 3, child: Text('${item.categoryName}${(item.beneficiary ?? '').isNotEmpty ? '\n${item.beneficiary}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 3, child: Text(item.description ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(backgroundColor: statusColor(context, item), label: Text(statusLabel(item))),
                      ),
                    ),
                    Expanded(flex: 2, child: Text(formatXaf(item.amount), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 46,
                      child: PopupMenuButton<String>(
                        tooltip: 'Actions',
                        onSelected: (value) {
                          switch (value) {
                            case 'proof': onProof(item); break;
                            case 'approve': onApprove(item); break;
                            case 'reject': onReject(item); break;
                            case 'resubmit': onResubmit(item); break;
                            case 'cancel': onCancel(item); break;
                          }
                        },
                        itemBuilder: (_) => [
                          if ((item.proofPath ?? '').isNotEmpty) const PopupMenuItem(value: 'proof', child: Text('Voir le justificatif')),
                          if (!OperatorSession.isReadOnly && item.isPending) ...const [
                            PopupMenuItem(value: 'approve', child: Text('Approuver')),
                            PopupMenuItem(value: 'reject', child: Text('Rejeter')),
                          ],
                          if (!OperatorSession.isReadOnly && item.isRejected) const PopupMenuItem(value: 'resubmit', child: Text('Resoumettre')),
                          if (!OperatorSession.isReadOnly && item.isApproved) const PopupMenuItem(value: 'cancel', child: Text('Annuler')),
                        ],
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseHeader extends StatelessWidget {
  const _ExpenseHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700));
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.item,
    required this.status,
    required this.statusColor,
    required this.onProof,
    required this.onApprove,
    required this.onReject,
    required this.onResubmit,
    required this.onCancel,
  });

  final ExpenseItem item;
  final String status;
  final Color statusColor;
  final VoidCallback onProof, onApprove, onReject, onResubmit, onCancel;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${item.expenseNumber ?? ''} · ${item.categoryName}', style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(formatXaf(item.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Chip(backgroundColor: statusColor, label: Text(status)),
              Chip(label: Text(DateFormat('dd/MM/yyyy').format(item.spentAt))),
              if ((item.paymentMethod ?? '').isNotEmpty) Chip(label: Text(item.paymentMethod!)),
            ]),
            if ((item.beneficiary ?? '').isNotEmpty) Text('Bénéficiaire : ${item.beneficiary}'),
            if ((item.description ?? '').isNotEmpty) Text(item.description!),
            if ((item.approvalNote ?? '').isNotEmpty) Text('Décision : ${item.approvalNote}', style: Theme.of(context).textTheme.bodySmall),
            if ((item.proofPath ?? '').isNotEmpty) TextButton.icon(onPressed: onProof, icon: const Icon(Icons.attach_file), label: const Text('Voir / télécharger le justificatif')),
            if (!OperatorSession.isReadOnly)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (item.isPending) ...[
                  TextButton.icon(onPressed: onReject, icon: const Icon(Icons.close), label: const Text('Rejeter')),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: onApprove, icon: const Icon(Icons.check), label: const Text('Approuver')),
                ] else if (item.isRejected)
                  FilledButton.tonalIcon(onPressed: onResubmit, icon: const Icon(Icons.refresh), label: const Text('Resoumettre'))
                else if (item.isApproved)
                  TextButton.icon(onPressed: onCancel, icon: const Icon(Icons.cancel_outlined), label: const Text('Annuler')),
              ]),
          ]),
        ),
      );
}
