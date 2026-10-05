import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';

class ManualJournalEntryScreen extends ConsumerStatefulWidget {
  const ManualJournalEntryScreen({super.key});
  @override
  ConsumerState<ManualJournalEntryScreen> createState() => _ManualJournalEntryScreenState();
}

class _ManualLine {
  String? accountCode;
  final debit = TextEditingController();
  final credit = TextEditingController();
  void dispose() {
    debit.dispose();
    credit.dispose();
  }
}

class _ManualJournalEntryScreenState extends ConsumerState<ManualJournalEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _description = TextEditingController();
  DateTime _date = DateTime.now();
  String _journal = 'OD';
  final _lines = <_ManualLine>[_ManualLine(), _ManualLine()];
  bool _saving = false;

  @override
  void dispose() {
    _reference.dispose();
    _description.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int _amount(String value) => int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  int get _debit => _lines.fold(0, (s, l) => s + _amount(l.debit.text));
  int get _credit => _lines.fold(0, (s, l) => s + _amount(l.credit.text));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(accountingRepositoryProvider).createManualEntry(
        date: _date,
        journalCode: _journal,
        reference: _reference.text,
        description: _description.text,
        lines: _lines
            .map((l) => {
                  'account_code': l.accountCode,
                  'label': _description.text,
                  'debit': _amount(l.debit.text),
                  'credit': _amount(l.credit.text)
                })
            .toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Écriture comptabilisée et auditée.')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nouvelle écriture manuelle')),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: ref.read(accountingRepositoryProvider).accounts(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final accounts = snap.data!;
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String>(
                          value: _journal,
                          decoration: const InputDecoration(labelText: 'Journal'),
                          items: const ['OD', 'VE', 'AC', 'CA', 'BQ', 'MM']
                              .map((j) => DropdownMenuItem(value: j, child: Text(j)))
                              .toList(),
                          onChanged: (v) => setState(() => _journal = v ?? _journal),
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Theme.of(context).dividerColor),
                          ),
                          title: const Text('Date'),
                          subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _date = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reference,
                    decoration: const InputDecoration(labelText: 'Référence / pièce'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Obligatoire' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration:
                        const InputDecoration(labelText: 'Libellé de l\'écriture'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Obligatoire' : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Lignes comptables',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  ..._lines.asMap().entries.map((entry) {
                    final i = entry.key;
                    final l = entry.value;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: l.accountCode,
                              isExpanded: true,
                              decoration: InputDecoration(labelText: 'Compte ${i + 1}'),
                              items: accounts
                                  .map((a) => DropdownMenuItem(
                                        value: '${a['code']}',
                                        child: Text('${a['code']} - ${a['label']}'),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => l.accountCode = v),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: l.debit,
                                    keyboardType: TextInputType.number,
                                    decoration:
                                        const InputDecoration(labelText: 'Débit'),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: l.credit,
                                    keyboardType: TextInputType.number,
                                    decoration:
                                        const InputDecoration(labelText: 'Crédit'),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _lines.add(_ManualLine())),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une ligne'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Contrôle d\'équilibre'),
                      subtitle: Text(
                        'Débit ${formatXaf(_debit)} · Crédit ${formatXaf(_credit)}',
                      ),
                      trailing: Icon(
                        _debit > 0 && _debit == _credit
                            ? Icons.check_circle
                            : Icons.error,
                        color: _debit > 0 && _debit == _credit
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(
                      _saving
                          ? 'Comptabilisation…'
                          : 'Comptabiliser l\'écriture',
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}
