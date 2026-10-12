import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/pdf_output_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../services/payment_notice_batch_pdf_service.dart';
import '../../services/document_number_service.dart';
import '../../services/student_media_service.dart';


String? resolvePaymentNoticeSchoolYearLabel({
  required List<SchoolYearItem> years,
  required String? selectedSchoolYearId,
  required String? establishmentLabel,
}) {
  if (selectedSchoolYearId != null) {
    for (final year in years) {
      if (year.id == selectedSchoolYearId) return year.label;
    }
  } else {
    for (final year in years) {
      if (year.isActive) return year.label;
    }
  }
  return establishmentLabel;
}


class PaymentNoticesScreen extends ConsumerStatefulWidget {
  const PaymentNoticesScreen({super.key});

  @override
  ConsumerState<PaymentNoticesScreen> createState() =>
      _PaymentNoticesScreenState();
}

class _PaymentNoticesScreenState
    extends ConsumerState<PaymentNoticesScreen> {
  String? _schoolYearId, _cycleId, _classroomId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _loading = false;
  List<StudentNoticeData> _preview = const [];
  final _search = TextEditingController();
  bool _selectionEnabled = false;
  final Set<String> _selectedIds = {};

  static const months = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];

  String get _periodKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  String get _periodLabel =>
      '${months[_month.month - 1]} ${_month.year}';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _resetPreview() {
    _preview = const [];
    _selectedIds.clear();
    _selectionEnabled = false;
  }

  Future<void> _pickMonth() async {
    var month = _month.month;
    var year = _month.year;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialog) => StatefulBuilder(builder: (context, update) =>
        AlertDialog(
          title: const Text('Mois des appels à paiement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true, initialValue: month,
                decoration: const InputDecoration(labelText: 'Mois'),
                items: [
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(months[i - 1]),
                    ),
                ],
                onChanged: (value) => update(() => month = value ?? month),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true, initialValue: year,
                decoration: const InputDecoration(labelText: 'Année'),
                items: [
                  for (var i = 2020; i <= 2100; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (value) => update(() => year = value ?? year),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, DateTime(year, month, 1)),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _month = selected;
        _resetPreview();
      });
    }
  }

  Future<List<StudentNoticeData>> _fetch() async {
    if (_classroomId == null) {
      throw StateError('Sélectionnez une classe avant de continuer.');
    }
    final rows = await ref.read(reportRepositoryProvider).billingDues(
      filter: ReportFilter(
        cycleId: _cycleId,
        classroomId: _classroomId,
        schoolYearId: _schoolYearId,
        periodKey: _periodKey,
      ),
    );
    return groupDuesByStudent(rows);
  }

  Future<void> _loadPreview() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final rows = await _fetch();
      if (!mounted) return;
      setState(() {
        _preview = rows;
        _selectionEnabled = false;
        _selectedIds.clear();
      });
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucune échéance impayée pour cette période.'),
        ));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aperçu indisponible : $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(StudentNoticeData student, bool enabled) {
    setState(() {
      if (!_selectionEnabled) {
        _selectionEnabled = true;
        _selectedIds.addAll(_preview.map((s) => s.studentId));
      }
      if (enabled) {
        _selectedIds.add(student.studentId);
      } else {
        _selectedIds.remove(student.studentId);
      }
    });
  }

  Future<void> _generatePdf() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final latest = await _fetch();
      if (!mounted) return;
      final selected = _selectionEnabled
          ? latest.where((s) => _selectedIds.contains(s.studentId)).toList()
          : latest;
      if (selected.isEmpty) {
        throw StateError('Aucun appel avec une dette à imprimer.');
      }
      final before = {
        for (final item in _preview) item.studentId: item.totalBalance,
      };
      final changed = selected.where(
        (item) => before.containsKey(item.studentId) &&
            before[item.studentId] != item.totalBalance,
      ).length;
      if (changed > 0) {
        final approved = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Montants actualisés'),
            content: Text(
              '$changed élève(s) ont un nouveau solde depuis l’aperçu. '
              'Les appels utiliseront les montants actuels. Continuer ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Générer avec les nouveaux montants'),
              ),
            ],
          ),
        );
        if (approved != true) {
          setState(() => _preview = latest);
          return;
        }
      }
      final establishment = await ref.read(establishmentProvider.future);
      final cycles = await ref.read(cyclesProvider.future);
      final classrooms = await ref.read(classroomsProvider.future);
      final years = await ref.read(schoolYearsProvider.future);
      final yearLabel = resolvePaymentNoticeSchoolYearLabel(
        years: years,
        selectedSchoolYearId: _schoolYearId,
        establishmentLabel: establishment?.schoolYearLabel,
      );
      final cycle = cycles.where((c) => c['id'] == _cycleId).toList();
      final classroom = classrooms.where(
        (c) => c.id == _classroomId,
      ).toList();
      final classLabel = classroom.isEmpty ? '' : classroom.first.name;
      final logoPath = establishment?.logoPath;
      final logo = (logoPath == null || logoPath.isEmpty) ? null
          : await StudentMediaService().readStoredFileBytes(logoPath);
      final registry = DocumentNumberService();
      final reference = await registry.getOrCreate(
        type: 'APP',
        entityId: '${_classroomId ?? ''}:$_periodKey:'
            '${DateTime.now().microsecondsSinceEpoch}',
      );
      final bytes = await PaymentNoticeBatchPdfService().build(
        students: selected,
        periodLabel: _periodLabel,
        establishmentName: establishment?.name,
        establishmentAddress: establishment?.address,
        establishmentPhone: establishment?.phone,
        establishmentEmail: establishment?.email,
        approvalNumber: establishment?.approvalNumber,
        schoolYearLabel: yearLabel,
        batchReference: reference,
        cycleLabel: cycle.isEmpty ? null : cycle.first['name'] as String?,
        classroomLabel: classLabel,
        logoBytes: logo,
      );
      await registry.recordFingerprint(reference: reference, bytes: bytes);
      final output = await outputPdf(
        bytes,
        fileName: 'Appels_paiement_${_periodKey}_$reference.pdf',
      );
      if (!mounted) return;
      setState(() => _preview = latest);
      if (output != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${selected.length} appels générés · Réf. $reference'),
        ));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Génération impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycles = ref.watch(cyclesProvider);
    final classrooms = ref.watch(classroomsProvider);
    final years = ref.watch(schoolYearsProvider);
    final search = _search.text.trim().toLowerCase();
    final visible = _preview.where((s) => [
      s.studentName, s.registrationNumber,
      s.guardianName, s.family,
    ].join(' ').toLowerCase().contains(search)).toList();
    final total = _preview.fold<int>(
      0, (sum, s) => sum + s.totalBalance,
    );
    final count = _selectionEnabled ? _selectedIds.length : _preview.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appels à paiement par classe'),
        actions: [
          IconButton(
            tooltip: 'Actualiser l’aperçu',
            onPressed: _loading ? null : _loadPreview,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Périmètre des appels',
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, size) {
                  final width = size.maxWidth >= 940
                      ? (size.maxWidth - 20) / 3
                      : size.maxWidth >= 600
                          ? (size.maxWidth - 10) / 2 : size.maxWidth;
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    SizedBox(width: width, child: years.when(
                      data: (items) {
                        final active = items.where((y) => y.isActive).firstOrNull;
                        final year = _schoolYearId ?? active?.id;
                        return DropdownButtonFormField<String>(
                          key: ValueKey('notice_year_$year'),
                          initialValue: items.any((y) => y.id == year)
                              ? year : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Année scolaire'),
                          items: items.map((y) => DropdownMenuItem(
                            value: y.id,
                            child: Text('${y.label}${y.isActive ? ' · en cours' : ''}',
                                overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() {
                            _schoolYearId = v;
                            _cycleId = null;
                            _classroomId = null;
                            _resetPreview();
                          }),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('$error'),
                    )),
                    SizedBox(width: width, child: cycles.when(
                      data: (items) => DropdownButtonFormField<String>(
                        key: ValueKey('notice_cycle_$_cycleId'),
                        initialValue: _cycleId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Cycle'),
                        hint: const Text('Choisir un cycle'),
                        items: items.map((c) => DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(c['name'] as String,
                              overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() {
                          _cycleId = v;
                          _classroomId = null;
                          _resetPreview();
                        }),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('$error'),
                    )),
                    SizedBox(width: width, child: classrooms.when(
                      data: (items) {
                        final shown = _cycleId == null ? items
                            : items.where((c) => c.cycleId == _cycleId).toList();
                        return DropdownButtonFormField<String>(
                          key: ValueKey('notice_class_${_cycleId}_$_classroomId'),
                          initialValue: shown.any((c) => c.id == _classroomId)
                              ? _classroomId : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Classe / Salle *'),
                          items: shown.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.cycleName} · ${c.name}',
                                overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() {
                            _classroomId = v;
                            _resetPreview();
                          }),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('$error'),
                    )),
                  ]);
                }),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickMonth,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Mois : $_periodLabel'),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, size) {
                  final width = size.maxWidth >= 570
                      ? (size.maxWidth - 10) / 2 : size.maxWidth;
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    SizedBox(width: width, child: OutlinedButton.icon(
                      onPressed: _loading ? null : _loadPreview,
                      icon: const Icon(Icons.search),
                      label: const Text('Voir les échéances'),
                    )),
                    SizedBox(width: width, child: FilledButton.icon(
                      onPressed: _loading ? null : _generatePdf,
                      icon: _loading
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text('Générer $count appel(s) PDF'),
                    )),
                  ]);
                }),
                const SizedBox(height: 7),
                const Text(
                  'Impression haute lisibilité : 2 avis par A4 '
                  '(1 page entière si plusieurs rubriques).',
                ),
              ],
            ),
          )),
        )),
        if (_preview.isNotEmpty) SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_preview.length} élève(s) · Montant total à régler : '
                  '${formatXaf(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Rechercher dans la classe',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 7),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selectionEnabled = false;
                    _selectedIds.clear();
                  }),
                  icon: const Icon(Icons.select_all),
                  label: const Text('Tous les élèves'),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selectionEnabled = true;
                    _selectedIds.clear();
                  }),
                  icon: const Icon(Icons.deselect),
                  label: const Text('Tout désélectionner'),
                ),
              ]),
            ],
          ),
        )),
        if (_preview.isNotEmpty)
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final student = visible[index];
              final checked = !_selectionEnabled ||
                  _selectedIds.contains(student.studentId);
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: CheckboxListTile(
                  value: checked,
                  onChanged: (enabled) =>
                      _select(student, enabled ?? false),
                  title: Text(student.studentName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${student.registrationNumber} · '
                    '${student.cycle} / ${student.classroom}\n'
                    '${student.lines.length} rubrique(s) · '
                    'Reste : ${formatXaf(student.totalBalance)}',
                  ),
                ),
              );
            },
          ),
      ]),
    );
  }
}
