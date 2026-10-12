import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/super_admin_service.dart';

enum SuperAdminHistoryKind { requests, activity }

class SuperAdminHistoryScreen extends StatefulWidget {
  const SuperAdminHistoryScreen({
    super.key,
    required this.kind,
    this.organizationId,
  });

  final SuperAdminHistoryKind kind;
  final String? organizationId;

  @override
  State<SuperAdminHistoryScreen> createState() => _SuperAdminHistoryScreenState();
}

class _SuperAdminHistoryScreenState extends State<SuperAdminHistoryScreen> {
  final _filter = TextEditingController();
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = widget.kind == SuperAdminHistoryKind.requests
          ? await SuperAdminService.instance.registrationHistory(
              offset: reset ? 0 : _rows.length)
          : await SuperAdminService.instance.activityHistory(
              organizationId: widget.organizationId,
              offset: reset ? 0 : _rows.length);
      final list = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(list);
        _more = data['has_more'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—'
        : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  static String _csvCell(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';

  Future<void> _copyCsv(List<Map<String, dynamic>> filtered) async {
    const requestFields = [
      'school_name', 'email', 'display_name',
      'status', 'created_at', 'reviewed_at', 'review_note',
    ];
    const eventFields = [
      'created_at', 'organization_id', 'event_type', 'module', 'message',
    ];
    final columns = widget.kind == SuperAdminHistoryKind.requests
        ? requestFields : eventFields;
    final lines = [
      columns.map(_csvCell).join(';'),
      for (final row in filtered)
        columns.map((column) => _csvCell(row[column])).join(';'),
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lignes visibles copiées en CSV. '
          'Collez-les dans Excel ou votre tableur.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _filter.text.trim().toLowerCase();
    final filtered = _rows.where((entry) =>
        query.isEmpty || entry.values.any((value) =>
            (value ?? '').toString().toLowerCase().contains(query)))
        .toList(growable: false);
    final requests = widget.kind == SuperAdminHistoryKind.requests;
    return Scaffold(
      appBar: AppBar(
        title: Text(requests ? 'Historique des demandes' : 'Journal SaaS'),
        actions: [
          IconButton(
            tooltip: 'Copier les résultats chargés en CSV',
            onPressed: filtered.isEmpty ? null : () => _copyCsv(filtered),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Filtrer les éléments chargés',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Text('${filtered.length} résultat(s) affiché(s) · '
                '${_rows.length} chargé(s)'),
            if (_error != null) ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Chargement interrompu'),
              subtitle: Text(_error!),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (filtered.isEmpty && !_loading)
              const ListTile(title: Text('Aucun élément correspondant.')),
            for (final item in filtered)
              Card(child: ListTile(
                leading: Icon(requests
                    ? item['status'] == 'approved'
                        ? Icons.check_circle_outline : Icons.cancel_outlined
                    : item['event_type'] == 'sync_error'
                        ? Icons.warning_amber_outlined : Icons.history),
                title: Text(requests
                    ? '${item['school_name'] ?? 'École'} · ${item['status'] ?? '—'}'
                    : item['message']?.toString() ?? item['event_type']?.toString() ?? 'Événement'),
                subtitle: Text(requests
                    ? '${item['display_name'] ?? '—'} · ${item['email'] ?? '—'}\n'
                      'Revue : ${_date(item['reviewed_at'])}'
                      '${(item['review_note'] ?? '').toString().isNotEmpty ? "\nMotif : ${item['review_note']}" : ""}'
                    : '${item['module'] ?? 'system'} · ${_date(item['created_at'])}\n'
                      'Établissement : ${item['organization_id'] ?? 'Plateforme'}'),
                isThreeLine: true,
              )),
            if (_more) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.expand_more),
                label: const Text('Charger 100 éléments supplémentaires'),
              ),
            ],
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
