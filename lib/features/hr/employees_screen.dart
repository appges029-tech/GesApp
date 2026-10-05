import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../data/models/hr.dart';
import 'employee_detail_screen.dart';
import 'employee_form_screen.dart';

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  final _query = TextEditingController();
  String? _status = 'active';
  List<EmployeeItem> _items = const [];
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _page = 60;

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
      _items = const [];
      _offset = 0;
      _hasMore = true;
    }
    if (!_hasMore) return;
    setState(() => _loading = true);
    final rows = await ref.read(hrRepositoryProvider).employees(
          query: _query.text,
          status: _status,
          limit: _page,
          offset: _offset,
        );
    if (!mounted) return;
    setState(() {
      _items = [..._items, ...rows];
      _offset += rows.length;
      _hasMore = rows.length == _page;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personnel'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Statut',
            onSelected: (value) {
              setState(() => _status = value == 'all' ? null : value);
              _load(reset: true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'active', child: Text('Actifs')),
              PopupMenuItem(value: 'suspended', child: Text('Suspendus')),
              PopupMenuItem(value: 'resigned', child: Text('Démissionnaires')),
              PopupMenuItem(value: 'terminated', child: Text('Licenciés')),
              PopupMenuItem(value: 'retired', child: Text('Retraités')),
              PopupMenuItem(value: 'all', child: Text('Tous')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const EmployeeFormScreen()),
          );
          if (result != null) await _load(reset: true);
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Employé'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              onSubmitted: (_) => _load(reset: true),
              decoration: InputDecoration(
                labelText: 'Matricule, nom, téléphone, poste ou service',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () => _load(reset: true),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('Aucun employé.'))
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        if (index == _items.length) {
                          return Center(
                            child: _loading
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: _load,
                                    child: const Text('Charger plus'),
                                  ),
                          );
                        }
                        final employee = _items[index];
                        final details = [
                          employee.employeeNumber,
                          employee.positionName,
                          employee.departmentName,
                          employee.phone,
                        ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(employee.firstName.isEmpty ? '?' : employee.firstName[0].toUpperCase()),
                            ),
                            title: Text(employee.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(details),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(builder: (_) => EmployeeDetailScreen(employeeId: employee.id)),
                              );
                              await _load(reset: true);
                            },
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
