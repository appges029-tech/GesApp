import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/widgets/stored_image.dart';
import '../../core/windows/windows_filter_panel.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/student.dart';
import 'document_verification_screen.dart';
import 'families_screen.dart';
import 'student_bulk_import_screen.dart';
import 'student_detail_screen.dart';
import 'student_form_screen.dart';

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});
  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _search = TextEditingController();
  String? _cycleId, _classroomId, _familyId, _status, _paymentStatus;
  List<Student> _items = const [];
  bool _loading = false, _hasMore = true;
  int _offset = 0;
  static const _page = 100;

  StudentFilter get _filter => StudentFilter(
        query: _search.text,
        cycleId: _cycleId,
        classroomId: _classroomId,
        familyId: _familyId,
        status: _status,
        paymentStatus: _paymentStatus,
      );

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
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
      final rows = await ref.read(studentRepositoryProvider).list(filter: _filter, limit: _page, offset: _offset);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...rows];
        _offset += rows.length;
        _hasMore = rows.length == _page;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear() {
    _search.clear();
    _cycleId = null;
    _classroomId = null;
    _familyId = null;
    _status = null;
    _paymentStatus = null;
    _load(reset: true);
  }

  Future<void> _openAdd() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentFormScreen()));
    await _load(reset: true);
  }

  Future<void> _openImport() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentBulkImportScreen()));
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final cycles = ref.watch(cyclesProvider);
    final classrooms = ref.watch(classroomsProvider);
    final families = ref.watch(familiesProvider);
    final desktop = WindowsUi.isDesktop(context);

    final filterWidgets = <Widget>[
      cycles.when(
        data: (items) => DropdownButtonFormField<String>(
          initialValue: _cycleId,
          decoration: const InputDecoration(labelText: 'Cycle'),
          isExpanded: true,
          items: items.map((r) => DropdownMenuItem(value: r['id'] as String, child: Text(r['name'] as String, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() {
            _cycleId = v;
            _classroomId = null;
          }),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
      ),
      classrooms.when(
        data: (items) {
          final shown = _cycleId == null ? items : items.where((c) => c.cycleId == _cycleId).toList();
          return DropdownButtonFormField<String>(
            initialValue: shown.any((c) => c.id == _classroomId) ? _classroomId : null,
            decoration: const InputDecoration(labelText: 'Classe'),
            isExpanded: true,
            items: shown.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.cycleName} · ${c.name}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _classroomId = v),
          );
        },
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
      ),
      families.when(
        data: (items) => DropdownButtonFormField<String>(
          initialValue: _familyId,
          decoration: const InputDecoration(labelText: 'Famille'),
          isExpanded: true,
          items: items.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _familyId = v),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
      ),
      DropdownButtonFormField<String>(
        initialValue: _status,
        decoration: const InputDecoration(labelText: 'Statut administratif'),
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'active', child: Text('Actif')),
          DropdownMenuItem(value: 'transfere', child: Text('Transféré')),
          DropdownMenuItem(value: 'exclu', child: Text('Exclu')),
          DropdownMenuItem(value: 'abandon', child: Text('Abandon')),
        ],
        onChanged: (v) => setState(() => _status = v),
      ),
      DropdownButtonFormField<String>(
        initialValue: _paymentStatus,
        decoration: const InputDecoration(labelText: 'Situation de paiement'),
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'paid', child: Text('À jour')),
          DropdownMenuItem(value: 'partial', child: Text('Partiellement payé')),
          DropdownMenuItem(value: 'unpaid', child: Text('Impayé')),
          DropdownMenuItem(value: 'overdue', child: Text('En retard')),
          DropdownMenuItem(value: 'no_due', child: Text('Aucune échéance')),
          DropdownMenuItem(value: 'package', child: Text('Forfait actif')),
        ],
        onChanged: (v) => setState(() => _paymentStatus = v),
      ),
    ];

    final filtersPanel = WindowsFilterPanel(
      active: _filter.isActive,
      onClear: _clear,
      onApply: () => _load(reset: true),
      search: TextField(
        controller: _search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Nom, matricule, parent ou téléphone',
          suffixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _load(reset: true),
          ),
        ),
        onSubmitted: (_) => _load(reset: true),
      ),
      filters: filterWidgets,
    );

    final desktopBody = Column(
      children: [
        filtersPanel,
        const SizedBox(height: 14),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(child: Text('Aucun élève pour ces critères.'))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: _StudentDesktopList(
                    students: _items,
                    hasMore: _hasMore,
                    loading: _loading,
                    onLoadMore: _load,
                    onOpen: _openStudent,
                  ),
                ),
        ),
        if (_loading && _items.isNotEmpty) const LinearProgressIndicator(),
      ],
    );

    final mobileBody = RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          filtersPanel,
          const SizedBox(height: 8),
          if (_items.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Aucun élève pour ces critères.')),
            )
          else ...[
            for (var i = 0; i < _items.length; i++) ...[
              _StudentCard(
                student: _items[i],
                onTap: () => _openStudent(_items[i]),
              ),
              if (i != _items.length - 1) const SizedBox(height: 8),
            ],
            if (_hasMore) ...[
              const SizedBox(height: 12),
              Center(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      )
                    : OutlinedButton(
                        onPressed: _load,
                        child: const Text('Charger plus'),
                      ),
              ),
            ],
          ],
          if (_loading && _items.isNotEmpty) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );

    return WindowsPageScaffold(
      title: 'Élèves',
      subtitle: desktop ? '${_items.length} élève(s) chargé(s) · recherche et filtres avancés' : null,
      actions: [
        WindowsCommandButton(
          icon: Icons.verified_outlined,
          label: 'Vérifier',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentVerificationScreen())),
        ),
        WindowsCommandButton(icon: Icons.upload_file, label: 'Importer', onPressed: _openImport),
        WindowsCommandButton(
          icon: Icons.family_restroom,
          label: 'Familles',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FamiliesScreen())),
        ),
        if (desktop) WindowsCommandButton(icon: Icons.person_add_alt_1, label: 'Inscrire', primary: true, onPressed: _openAdd),
      ],
      floatingActionButton: desktop ? null : FloatingActionButton.extended(onPressed: _openAdd, icon: const Icon(Icons.person_add_alt_1), label: const Text('Inscrire')),
      body: desktop ? desktopBody : mobileBody,
    );
  }

  Future<void> _openStudent(Student student) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => StudentDetailScreen(student: student)));
    await _load(reset: true);
  }
}

class _StudentDesktopList extends StatelessWidget {
  const _StudentDesktopList({required this.students, required this.hasMore, required this.loading, required this.onLoadMore, required this.onOpen});

  final List<Student> students;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;
  final ValueChanged<Student> onOpen;

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
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
            child: const Row(children: [
              Expanded(flex: 4, child: _HeaderText('Élève')),
              Expanded(flex: 2, child: _HeaderText('Matricule')),
              Expanded(flex: 3, child: _HeaderText('Classe')),
              Expanded(flex: 3, child: _HeaderText('Famille / responsable')),
              Expanded(flex: 2, child: _HeaderText('Paiement')),
              SizedBox(width: 36),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: students.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .55)),
              itemBuilder: (context, index) {
                if (index == students.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(child: loading ? const CircularProgressIndicator() : OutlinedButton(onPressed: onLoadMore, child: const Text('Charger plus'))),
                  );
                }
                final student = students[index];
                return InkWell(
                  onTap: () => onOpen(student),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(children: [
                      Expanded(
                        flex: 4,
                        child: Row(children: [
                          ClipOval(
                            child: StoredImage(
                              reference: student.photoPath,
                              width: 32,
                              height: 32,
                              fallback: CircleAvatar(radius: 16, child: Text(student.lastName.isEmpty ? '?' : student.lastName[0].toUpperCase())),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: Text(student.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                      Expanded(flex: 2, child: Text(student.registrationNumber ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 3, child: Text('${student.cycleName} · ${student.classroomName}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 3, child: Text(student.familyName ?? student.guardianName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: Text(_paymentLabel(student), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 36, child: Icon(Icons.chevron_right_rounded, size: 18)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _paymentLabel(Student student) {
    final label = switch (student.paymentStatus) {
      'paid' => 'À jour',
      'partial' => 'Partiel',
      'overdue' => 'En retard',
      'unpaid' => 'Impayé',
      _ => 'Sans échéance',
    };
    return student.hasPackage ? '$label · Forfait' : label;
  }
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700));
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.onTap});
  final Student student;
  final VoidCallback onTap;
  String _pay(String s) => switch (s) {
        'paid' => 'À jour',
        'partial' => 'Partiel',
        'overdue' => 'En retard',
        'unpaid' => 'Impayé',
        _ => 'Sans échéance',
      };
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          leading: ClipOval(
            child: StoredImage(
              reference: student.photoPath,
              width: 40,
              height: 40,
              fallback: CircleAvatar(child: Text(student.lastName.isEmpty ? '?' : student.lastName[0].toUpperCase())),
            ),
          ),
          title: Text(student.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${student.cycleName} · ${student.classroomName}\n${student.registrationNumber ?? 'Sans matricule'} · ${_pay(student.paymentStatus)}${student.hasPackage ? ' · Forfait' : ''}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
