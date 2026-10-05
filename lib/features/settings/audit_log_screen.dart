import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/platform/download_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../data/repositories/audit_repository.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final _query = TextEditingController();
  List<AuditEntry> _items = const [];
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _type;
  static const _pageSize = 100;

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
    try {
      final rows = await ref.read(auditRepositoryProvider).search(
            query: _query.text,
            entityType: _type,
            limit: _pageSize,
            offset: _offset,
          );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...rows];
        _offset += rows.length;
        _hasMore = rows.length == _pageSize;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    final rows = await ref.read(auditRepositoryProvider).search(
          query: _query.text,
          entityType: _type,
          limit: 5000,
        );
    final buffer = StringBuffer('date;operateur;type;entite;action;avant;apres\n');
    String escape(String value) => '"${value.replaceAll('"', '""').replaceAll('\n', ' ')}"';
    for (final row in rows) {
      buffer.writeln([
        row.createdAt.toIso8601String(),
        row.operatorName,
        row.entityType,
        row.entityId,
        row.action,
        row.oldValue ?? '',
        row.newValue ?? '',
      ].map(escape).join(';'));
    }
    await downloadBytes(
      bytes: Uint8List.fromList(utf8.encode('\uFEFF${buffer.toString()}')),
      fileName: 'journal_audit_${DateTime.now().toIso8601String().split('T').first}.csv',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  String _label(String action) => switch (action) {
        'create' => 'Création',
        'cancel' => 'Annulation',
        'generate' => 'Génération',
        'status_change' => 'Changement de statut',
        'reenroll' => 'Réinscription',
        'bulk_import_transactional' => 'Import massif',
        _ => action,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d’audit'),
        actions: [
          IconButton(
            tooltip: 'Exporter CSV',
            onPressed: _export,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    onSubmitted: (_) => _load(reset: true),
                    decoration: InputDecoration(
                      labelText: 'Rechercher',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        onPressed: () => _load(reset: true),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _type,
                  hint: const Text('Type'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tous')),
                    DropdownMenuItem(value: 'payment', child: Text('Paiement')),
                    DropdownMenuItem(value: 'expense', child: Text('Dépense')),
                    DropdownMenuItem(value: 'student', child: Text('Élève')),
                    DropdownMenuItem(value: 'cash_transfer', child: Text('Transfert')),
                    DropdownMenuItem(value: 'recurring_expense', child: Text('Dépense récurrente')),
                  ],
                  onChanged: (value) {
                    setState(() => _type = value);
                    _load(reset: true);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('Aucune opération auditée.'))
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: _load,
                                      child: const Text('Charger plus'),
                                    ),
                            ),
                          );
                        }
                        final item = _items[index];
                        final details = [
                          if ((item.oldValue ?? '').isNotEmpty) 'Avant : ${item.oldValue}',
                          if ((item.newValue ?? '').isNotEmpty) 'Après / détail : ${item.newValue}',
                        ].join('\n');
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.history_outlined),
                            title: Text(
                              '${_label(item.action)} · ${item.entityType}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt)} · ${item.operatorName}'
                              '${details.isEmpty ? '' : '\n$details'}',
                            ),
                            isThreeLine: details.isNotEmpty,
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (_loading && _items.isNotEmpty) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
