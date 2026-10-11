import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';

class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  String? _account;
  Map<String, Object?>? _session;
  List<Map<String, Object?>> _accounts = [];
  List<Map<String, Object?>> _transfers = [];
  String? _transferFrom;
  String? _transferTo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, Object?>? get _selectedAccount {
    final id = _account;
    if (id == null) return null;
    for (final account in _accounts) {
      if (account['id'] == id) return account;
    }
    return null;
  }

  Future<void> _load() async {
    final repo = ref.read(cashRepositoryProvider);
    final accounts = await repo.accounts();
    final selected = _account ?? (accounts.isEmpty ? null : accounts.first['id'] as String?);
    final selectedRow = accounts.where((a) => a['id'] == selected).firstOrNull;
    final session = selected != null && selectedRow?['type'] == 'cash'
        ? await repo.openSession(selected)
        : null;
    final transfers = await repo.transfers();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _account = selected;
      _session = session;
      _transfers = transfers;
      _transferFrom ??= accounts.isEmpty ? null : accounts.first['id'] as String?;
      _transferTo ??= accounts.length < 2 ? null : accounts[1]['id'] as String?;
    });
  }

  Future<int?> _amount(String title) async {
    String input = '';
    String? validationError;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text(title),
          content: TextFormField(
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Montant FCFA',
              errorText: validationError,
            ),
            onChanged: (value) => input = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(input.replaceAll(RegExp(r'\D'), ''));
                if (value == null || value < 0) {
                  refresh(() => validationError = 'Saisissez un montant valide.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCash() async {
    final account = _account;
    if (account == null) return;
    final amount = await _amount('Fond initial');
    if (amount == null || !mounted) return;
    try {
      await ref.read(cashRepositoryProvider).open(accountId: account, openingAmount: amount);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _closeCash(int theoretical) async {
    final session = _session;
    if (session == null) return;
    final physical = await _amount('Comptage physique');
    if (physical == null || !mounted) return;
    try {
      await ref.read(cashRepositoryProvider).close(
            sessionId: session['id'] as String,
            physicalAmount: physical,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clôture effectuée. Écart : ${formatXaf(physical - theoretical)}')),
      );
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _transfer() async {
    final from = _transferFrom;
    final to = _transferTo;
    if (from == null || to == null || from == to || _busy) return;
    String rawAmount = '';
    String reference = '';
    String note = '';
    String? error;
    final input = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Transfert interne'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Montant *', errorText: error),
                onChanged: (value) => rawAmount = value,
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Référence'),
                onChanged: (value) => reference = value,
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Note'),
                onChanged: (value) => note = value,
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final amount = int.tryParse(rawAmount.replaceAll(RegExp(r'\D'), ''));
                if (amount == null || amount <= 0) {
                  refresh(() => error = 'Saisissez un montant supérieur à zéro.');
                  return;
                }
                Navigator.pop(dialogContext, {
                  'amount': amount.toString(),
                  'reference': reference,
                  'note': note,
                });
              },
              child: const Text('Transférer'),
            ),
          ],
        ),
      ),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(cashRepositoryProvider).transfer(
        fromAccountId: from,
        toAccountId: to,
        amount: int.parse(input['amount']!),
        reference: input['reference'] ?? '',
        note: input['note'] ?? '',
      );
      ref.invalidate(auditEntriesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfert de ${formatXaf(int.parse(input['amount']!))} enregistré.')),
      );
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedAccount;
    final isPhysicalCash = selected?['type'] == 'cash';
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse & trésorerie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Ma caisse', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _account,
            decoration: const InputDecoration(labelText: 'Caisse / compte'),
            items: _accounts
                .map((account) => DropdownMenuItem(value: account['id'] as String, child: Text(account['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (value) async {
              _account = value;
              await _load();
            },
          ),
          const SizedBox(height: 16),
          if (!isPhysicalCash)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Compte non physique'),
                subtitle: Text('Les comptes Banque/Mobile Money ne nécessitent pas d’ouverture de caisse.'),
              ),
            )
          else if (_session == null)
            Card(
              child: ListTile(
                title: const Text('Caisse fermée'),
                subtitle: const Text('Pour recevoir des paiements en espèces, ouvrez la caisse.'),
                trailing: OperatorSession.isReadOnly ? null : FilledButton(onPressed: _account == null ? null : _openCash, child: const Text('Ouvrir')),
              ),
            )
          else
            FutureBuilder<int>(
              future: ref.read(cashRepositoryProvider).theoretical(_session!['id'] as String),
              builder: (context, snapshot) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Caisse ouverte', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('Fond initial : ${formatXaf(_session!['opening_amount'] as int)}'),
                      Text('Solde théorique : ${snapshot.hasData ? formatXaf(snapshot.data!) : 'Calcul…'}'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: OperatorSession.isReadOnly || !snapshot.hasData ? null : () => _closeCash(snapshot.data!),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Clôturer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!OperatorSession.isReadOnly)
            ExpansionTile(
              title: const Text('Options avancées de trésorerie'),
              subtitle: const Text('Transférer un montant entre deux comptes'),
              childrenPadding: const EdgeInsets.symmetric(vertical: 12),
              children: [
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
            isExpanded: true,
                    initialValue: _transferFrom,
                    decoration: const InputDecoration(labelText: 'Depuis'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _transferFrom = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
            isExpanded: true,
                    initialValue: _transferTo,
                    decoration: const InputDecoration(labelText: 'Vers'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _transferTo = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _transferFrom == null || _transferTo == null || _transferFrom == _transferTo ? null : _transfer,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Enregistrer un transfert'),
            ),
            ],
          ),
          const SizedBox(height: 20),
          if (_transfers.isNotEmpty)
            ExpansionTile(
              title: const Text('Historique des transferts'),
              subtitle: Text(_transfers.length.toString() + ' mouvement(s) enregistré(s)'),
              children: [

            ..._transfers.take(20).map(
                  (t) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_arrows),
                      title: Text('${t['from_name']} → ${t['to_name']}'),
                      subtitle: Text('${t['transferred_at']}${t['reference'] == null ? '' : ' · ${t['reference']}'}'),
                      trailing: Text(formatXaf(t['amount'] as int), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
