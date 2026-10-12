import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/platform/pdf_output_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_filter_panel.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/repositories/report_repository.dart';
import '../../services/bilan_financier_pdf_service.dart';
import '../../services/billing_pdf_service.dart';
import '../../services/unpaid_report_presenter.dart';
import '../../services/document_identity.dart';
import '../../services/document_number_service.dart';
import '../../services/excel_export_service.dart';
import '../../services/report_pdf_service.dart';
import 'payment_notices_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _cycleId, _classroomId, _familyId, _schoolYearId;
  DateTime? _start, _end;

  ReportFilter get _filter => ReportFilter(
        cycleId: _cycleId,
        classroomId: _classroomId,
        familyId: _familyId,
        schoolYearId: _schoolYearId,
        start: _start,
        end: _end?.add(const Duration(days: 1)),
      );

  Future<void> _pickDate(bool start) async {
    final initial = start ? (_start ?? DateTime.now()) : (_end ?? DateTime.now());
    final value = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: initial);
    if (value != null && mounted) {
      setState(() {
        if (start) {
          _start = value;
        } else {
          _end = value;
        }
      });
    }
  }

  void _clear() => setState(() {
        _cycleId = null;
        _classroomId = null;
        _familyId = null;
        _schoolYearId = null;
        _start = null;
        _end = null;
      });

  @override
  Widget build(BuildContext context) {
    final cycles = ref.watch(cyclesProvider);
    final classes = ref.watch(classroomsProvider);
    final families = ref.watch(familiesProvider);
    final years = ref.watch(schoolYearsProvider);
    final desktop = WindowsUi.isDesktop(context);

    final filters = <Widget>[
      years.when(
        data: (items) => DropdownButtonFormField<String>(
          initialValue: _schoolYearId,
          decoration: const InputDecoration(labelText: 'Année scolaire'),
          hint: const Text('Année active'),
          isExpanded: true,
          items: items.map((y) => DropdownMenuItem(value: y.id, child: Text('${y.label}${y.isActive ? ' · active' : ''}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _schoolYearId = v),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
      ),
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
      classes.when(
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
      OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.date_range), label: Text(_start == null ? 'Date de début' : _start!.toIso8601String().split('T').first)),
      OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event), label: Text(_end == null ? 'Date de fin' : _end!.toIso8601String().split('T').first)),
    ];

    final modules = <Widget>[
      _tile('Journal de caisse', Icons.menu_book_outlined, () => _openTable(title: 'Journal de caisse', headers: _cashHeaders(), rowsFuture: ref.read(reportRepositoryProvider).cashJournal(filter: _filter), mapper: _cashRow)),
      _tile('Liste des impayés', Icons.warning_amber_outlined, () => _openTable(title: 'Impayés', headers: _unpaidHeaders(), rowsFuture: ref.read(reportRepositoryProvider).unpaid(filter: _filter), mapper: _unpaidRow)),
      _tile('Ancienneté des impayés', Icons.timelapse_outlined, () => _openTable(title: 'Ancienneté des impayés', headers: const ['Ancienneté', 'Solde'], rowsFuture: ref.read(reportRepositoryProvider).agingReport(filter: _filter), mapper: (r) => ['${r['anciennete']}', formatXaf(r['solde'] as int)])),
      _tile('Recouvrement par cycle', Icons.pie_chart_outline, () => _openRecoveryPerformance('cycle', 'Recouvrement par cycle')),
      _tile('Recouvrement par classe', Icons.school_outlined, () => _openRecoveryPerformance('classroom', 'Recouvrement par classe')),
      _tile('Recouvrement par rubrique', Icons.category_outlined, () => _openRecoveryPerformance('fee', 'Recouvrement par rubrique')),
      _tile('Effectifs et statuts administratifs', Icons.groups_2_outlined, () => _openTable(title: 'Effectifs et statuts', headers: const ['Cycle', 'Classe', 'Statut', 'Total'], rowsFuture: ref.read(reportRepositoryProvider).enrollmentStatusReport(filter: _filter), mapper: (r) => ['${r['cycle']}', '${r['classroom']}', '${r['status']}', '${r['total']}'])),
      _tile('Dossiers élèves incomplets', Icons.folder_off_outlined, () => _openTable(title: 'Dossiers incomplets', headers: const ['Matricule', 'Élève', 'Cycle', 'Classe', 'Présentes', 'Requises', 'Manquantes'], rowsFuture: ref.read(reportRepositoryProvider).incompleteStudentFiles(filter: _filter), mapper: (r) => ['${r['registration_number']}', '${r['student']}', '${r['cycle']}', '${r['classroom']}', '${r['present_count']}', '${r['required_count']}', '${r['missing'] ?? ''}'])),
      _tile('Avis d’échéance / factures', Icons.request_quote_outlined, _billing),
      _tile('Appels à paiement par classe', Icons.mark_email_read_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentNoticesScreen()))),
      _tile('Livre de trésorerie', Icons.account_balance_wallet_outlined, _ledger),
      _tile('Rapport de dépenses', Icons.receipt_long_outlined, () => _openTable(title: 'Dépenses par catégorie', headers: _expenseHeaders(), rowsFuture: ref.read(reportRepositoryProvider).expenseReport(filter: _filter), mapper: _expenseRow)),
      _tile('Bilan financier', Icons.account_balance_outlined, _recovery),
    ];

    return WindowsPageScaffold(
      title: 'Rapports',
      subtitle: 'Analyses financières, recouvrement, effectifs et documents',
      body: ListView(
        padding: desktop ? EdgeInsets.zero : const EdgeInsets.all(16),
        children: [
          WindowsFilterPanel(
            search: Text('Périmètre : ${_filterLabel()}', style: Theme.of(context).textTheme.titleSmall),
            filters: filters,
            active: _filterLabel() != 'Toutes les données',
            onClear: _clear,
          ),
          const SizedBox(height: 16),
          WindowsModuleGrid(children: modules),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  String _filterLabel() {
    final parts = <String>[];
    if (_schoolYearId != null) parts.add('année scolaire');
    if (_cycleId != null) parts.add('cycle');
    if (_classroomId != null) parts.add('classe');
    if (_familyId != null) parts.add('famille');
    if (_start != null || _end != null) parts.add('période');
    return parts.isEmpty ? 'Toutes les données' : parts.join(' · ');
  }

  Widget _tile(String title, IconData icon, VoidCallback onTap) => WindowsModuleCard(
        icon: icon,
        title: title,
        subtitle: 'Ouvrir le rapport avec les filtres sélectionnés',
        onTap: onTap,
      );

  static List<String> _cashHeaders() => const ['Date', 'Type', 'Référence', 'Montant', 'Description'];
  static List<String> _cashRow(Map<String, Object?> r) => ['${r['date']}'.split('T').first, '${r['type']}', '${r['reference']}', formatXaf(r['amount'] as int), '${r['description']}'];
  static List<String> _unpaidHeaders() => const ['Matricule', 'Élève', 'Cycle', 'Classe', 'Famille', 'Rubrique', 'Période', 'Dû', 'Payé', 'Solde', 'Échéance'];
  static List<String> _unpaidRow(Map<String, Object?> r) => ['${r['registration_number'] ?? ''}', '${r['student']}', '${r['cycle']}', '${r['classroom']}', '${r['family'] ?? ''}', '${r['fee']}', '${r['period_key']}', formatXaf(r['amount_due'] as int), formatXaf(r['amount_paid'] as int), formatXaf(r['balance'] as int), r['due_date'] == null ? '' : '${r['due_date']}'.split('T').first];
  static List<String> _expenseHeaders() => const ['Catégorie', 'Opérations', 'Total'];
  static List<String> _expenseRow(Map<String, Object?> r) => ['${r['category']}', '${r['operations']}', formatXaf(r['total'] as int)];

  Future<({String label, String? schoolYear})> _exportScope() async {
    final years = await ref.read(schoolYearsProvider.future);
    final year = years.where((y) => y.id == _schoolYearId ||
        (_schoolYearId == null && y.isActive)).firstOrNull;
    final scope = <String>[
      if (year != null) 'Année scolaire : ${year.label}',
      if (_cycleId != null) 'Cycle : ${(await ref.read(cyclesProvider.future))
          .where((cycle) => cycle['id'] == _cycleId)
          .map((cycle) => cycle['name']).firstOrNull ?? _cycleId}',
      if (_classroomId != null) 'Classe : ${(await ref.read(classroomsProvider.future))
          .where((room) => room.id == _classroomId)
          .map((room) => room.name).firstOrNull ?? _classroomId}',
      if (_familyId != null) 'Famille : ${(await ref.read(familiesProvider.future))
          .where((family) => family.id == _familyId)
          .map((family) => family.name).firstOrNull ?? _familyId}',
      if (_start != null) 'Du ${_start!.day}/${_start!.month}/${_start!.year}',
      if (_end != null) 'au ${_end!.day}/${_end!.month}/${_end!.year}',
    ];
    return (label: scope.join(' · '), schoolYear: year?.label);
  }

  Future<void> _openTable({
    required String title,
    required List<String> headers,
    required Future<List<Map<String, Object?>>> rowsFuture,
    required List<String> Function(Map<String, Object?>) mapper,
  }) async {
    try {
      final rows = await rowsFuture;
      final scope = await _exportScope();
      if (!mounted) return;
      final displayed = title == 'Impayés'
          ? UnpaidReportPresenter.rows(rows)
          : rows.map(mapper).toList(growable: false);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _ReportTableScreen(
          title: title, headers: headers, rows: displayed,
          scopeLabel: scope.label, schoolYearLabel: scope.schoolYear,
        ),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapport indisponible : $error')));
    }
  }

  Future<void> _openRecoveryPerformance(String groupBy, String title) async {
    final rows = await ref.read(reportRepositoryProvider).recoveryPerformance(filter: _filter, groupBy: groupBy);
    if (!mounted) return;
    final tableRows = rows.map((row) {
      final rawRate = row['rate'];
      final rate = rawRate is num ? rawRate.toDouble() : double.tryParse('$rawRate') ?? 0;
      return ['${row['label']}', '${row['students_count']}', '${row['dues_count']}', formatXaf(row['expected'] as int), formatXaf(row['collected'] as int), formatXaf(row['outstanding'] as int), '${rate.toStringAsFixed(1)} %'];
    }).toList();
    final scope = await _exportScope();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
      _ReportTableScreen(
        title: title,
        headers: const ['Groupe', 'Élèves', 'Échéances', 'Attendu', 'Payé', 'Reste', 'Taux'],
        rows: tableRows, scopeLabel: scope.label,
        schoolYearLabel: scope.schoolYear,
      )));
  }

  Future<void> _ledger() async {
    final entries = await ref.read(reportRepositoryProvider).grandLedger(filter: _filter);
    if (!mounted) return;
    final rows = entries.map((e) => [e.date.toIso8601String().split('T').first, e.reference, e.description, e.debit == 0 ? '' : formatXaf(e.debit), e.credit == 0 ? '' : formatXaf(e.credit), formatXaf(e.balance)]).toList();
    final scope = await _exportScope();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _ReportTableScreen(
      title: 'Livre de trésorerie',
      headers: const ['Date', 'Référence', 'Libellé', 'Débit', 'Crédit', 'Solde'],
      rows: rows, scopeLabel: scope.label,
      schoolYearLabel: scope.schoolYear,
    )));
  }

  Future<void> _billing() async {
    final dues = await ref.read(reportRepositoryProvider).billingDues(filter: _filter);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Avis d’échéance / factures')),
          body: dues.isEmpty
              ? const Center(child: Text('Aucune échéance pour ces filtres.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: dues.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final due = dues[i];
                    return Card(
                      child: ListTile(
                        title: Text('${due['student']} · ${due['fee']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${due['registration_number']} · ${due['cycle']} / ${due['classroom']}\n${due['period_key']} · reste ${formatXaf(due['balance'] as int)}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (kind) => _printBilling(due['due_id'] as String, invoice: kind == 'invoice'),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'notice', child: Text('Avis d’échéance PDF')),
                            PopupMenuItem(value: 'invoice', child: Text('Facture détaillée PDF')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _printBilling(String dueId, {required bool invoice}) async {
    final data = await ref.read(reportRepositoryProvider).billingDetail(dueId);
    final establishment = await ref.read(establishmentProvider.future);
    final identity = await DocumentIdentity.fromEstablishment(establishment);
    final registry = DocumentNumberService();
    final reference = await registry.getOrCreate(type: invoice ? 'FAC' : 'ECH', entityId: dueId);
    final bytes = await BillingPdfService().build(data: data, invoice: invoice, reference: reference, identity: identity);
    await registry.recordFingerprint(reference: reference, bytes: bytes);
    await outputPdf(bytes, fileName: '${invoice ? 'Facture' : 'Avis_echeance'}_$reference.pdf');
  }

  Future<void> _recovery() async {
    if (!mounted) return;
    final years = await ref.read(schoolYearsProvider.future);
    final matches = _schoolYearId == null
        ? years.where((y) => y.isActive).toList()
        : years.where((y) => y.id == _schoolYearId).toList();
    final selected = matches.isEmpty ? null : matches.first;
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _BilanFinancierScreen(
      schoolYearId: selected?.id,
      schoolYearLabel: selected?.label,
      initialStart: selected?.startDate,
      initialEnd: selected?.endDate,
    )));
  }
}
class _BilanFinancierScreen extends ConsumerStatefulWidget {
  const _BilanFinancierScreen({this.schoolYearId,this.schoolYearLabel,this.initialStart,this.initialEnd});
  final String? schoolYearId,schoolYearLabel;
  final DateTime? initialStart,initialEnd;
  @override
  ConsumerState<_BilanFinancierScreen> createState() => _BilanFinancierScreenState();
}

class _BilanFinancierScreenState extends ConsumerState<_BilanFinancierScreen> {
  bool _loading = true;
  bool _exporting = false;
  String? _loadError;
  FinancialReportSummary? _global;
  late DateTime _start;
  late DateTime _end;
  List<Map<String, Object?>> _trend = const [];
  List<Map<String, Object?>> _expenses = const [];
  List<Map<String, Object?>> _recovery = const [];
  String? _establishmentName, _establishmentAddress, _establishmentPhone, _schoolYearLabel;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = widget.initialStart ?? DateTime(now.year, now.month, 1);
    _end = widget.initialEnd ?? DateTime(now.year, now.month, now.day);
    _load();
  }

  DateTime get _exclusiveEnd => DateTime(_end.year, _end.month, _end.day + 1);
  String _dateLabel(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  String get _periodLabel => 'Du ${_dateLabel(_start)} au ${_dateLabel(_end)}';

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: 'Choisir la période du bilan',
      saveText: 'Appliquer',
    );
    if (selected == null || !mounted) return;
    setState(() { _start = selected.start; _end = selected.end; });
    await _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final repo = ref.read(reportRepositoryProvider);
      final filter = ReportFilter(start: _start, end: _exclusiveEnd, schoolYearId: widget.schoolYearId);
      final results = await Future.wait([
        repo.financialSummary(start: _start, end: _exclusiveEnd, schoolYearId: widget.schoolYearId),
        repo.monthlyFinancialTrend(start: _start, end: _exclusiveEnd, schoolYearId: widget.schoolYearId),
        repo.expenseReport(filter: filter),
        repo.recoveryPerformance(filter: filter, groupBy: 'cycle'),
        ref.read(establishmentProvider.future),
      ]);
      if (!mounted) return;
      final establishment = results[4] as dynamic;
      setState(() {
        _global = results[0] as FinancialReportSummary;
        _trend = results[1] as List<Map<String, Object?>>;
        _expenses = results[2] as List<Map<String, Object?>>;
        _recovery = results[3] as List<Map<String, Object?>>;
        _establishmentName = establishment?.name;
        _establishmentAddress = establishment?.address;
        _establishmentPhone = establishment?.phone;
        _schoolYearLabel = widget.schoolYearLabel ?? establishment?.schoolYearLabel;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _loadError = '$error'; });
    }
  }

  Future<void> _exportPdf() async {
    if (_global == null) return;
    setState(() => _exporting = true);
    try {
      final establishment = await ref.read(establishmentProvider.future);
      final identity = await DocumentIdentity.fromEstablishment(establishment);
      final registry = DocumentNumberService();
      final reference = await registry.getOrCreate(type: 'BIL', entityId: '${_start.toIso8601String()}-${_end.toIso8601String()}-${DateTime.now().microsecondsSinceEpoch}');
      final bytes = await BilanFinancierPdfService().build(
        global: _global!,
        monthlyTrend: _trend,
        expensesByCategory: _expenses,
        recoveryByCycle: _recovery,
        establishmentName: _establishmentName,
        establishmentAddress: _establishmentAddress,
        establishmentPhone: _establishmentPhone,
        schoolYearLabel: _schoolYearLabel,
        periodLabel: 'Bilan financier — $_periodLabel',
        identity: identity,
        reference: reference,
      );
      await registry.recordFingerprint(reference: reference, bytes: bytes);
      final destination = await outputPdf(bytes, fileName: 'Bilan_${_start.toIso8601String().split('T').first}_${_end.toIso8601String().split('T').first}_$reference.pdf');
      if (mounted && destination != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bilan PDF enregistré : $destination')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export PDF impossible : $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilan financier'),
        actions: [
          IconButton(
            tooltip: 'Générer le PDF détaillé',
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: (_loading || _exporting) ? null : _exportPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text('Impossible de charger le bilan : $_loadError', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
                ])))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.date_range_outlined),
                    title: const Text('Période du tableau de bord', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(_periodLabel),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickRange,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _exporting ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(_exporting ? 'Génération…' : 'Générer le bilan complet en PDF'),
                ),
                const SizedBox(height: 16),
                Text('Situation sur la période sélectionnée', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _kpiWrap([
                  _kpi('Attendu', formatXaf(_global!.expected), Colors.blueGrey),
                  _kpi('Encaissé', formatXaf(_global!.allocated), Colors.green.shade700),
                  _kpi('Reste à recouvrer', formatXaf(_global!.outstanding), Colors.orange.shade800),
                  _kpi('Taux de recouvrement', '${(_global!.recoveryRate * 100).toStringAsFixed(1)} %', Colors.indigo),
                  _kpi('Recettes', formatXaf(_global!.revenue), Colors.green.shade700),
                  _kpi('Dépenses', formatXaf(_global!.expenses), Colors.red.shade700),
                ]),
                const SizedBox(height: 8),
                Card(
                  color: _global!.cashBalance >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                  child: ListTile(
                    leading: Icon(Icons.savings_outlined, color: _global!.cashBalance >= 0 ? Colors.green.shade800 : Colors.red.shade800),
                    title: const Text('Bénéfice net de l’école', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Recettes encaissées − dépenses'),
                    trailing: Text(
                      formatXaf(_global!.cashBalance),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _global!.cashBalance >= 0 ? Colors.green.shade800 : Colors.red.shade800),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Évolution sur la période', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Card(child: Padding(padding: const EdgeInsets.all(12), child: _trendBars())),
                const SizedBox(height: 20),
                if (_expenses.isNotEmpty) ...[
                  Text('Dépenses par catégorie', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Card(child: Padding(padding: const EdgeInsets.all(12), child: _horizontalBars(_expenses, labelKey: 'category', valueKey: 'total', color: Colors.red.shade700, isPercent: false))),
                  const SizedBox(height: 20),
                ],
                if (_recovery.isNotEmpty) ...[
                  Text('Recouvrement par cycle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Card(child: Padding(padding: const EdgeInsets.all(12), child: _horizontalBars(_recovery, labelKey: 'label', valueKey: 'rate', color: Colors.indigo, isPercent: true))),
                ],
                const SizedBox(height: 12),
                Text(
                  'Le PDF exporté contient l’intégralité de ces indicateurs avec des graphiques imprimables.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                ),
              ],
            ),
    );
  }

  Widget _kpiWrap(List<Widget> children) => Wrap(spacing: 8, runSpacing: 8, children: children);

  Widget _kpi(String label, String value, Color color) => Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );

  Widget _trendBars() {
    if (_trend.isEmpty) return const Text('Aucune donnée');
    final maxValue = _trend.fold<num>(1, (max, r) {
      final rev = (r['revenue'] as num?) ?? 0;
      final exp = (r['expenses'] as num?) ?? 0;
      return [max, rev, exp].reduce((a, b) => a > b ? a : b);
    });
    return Column(
      children: [
        Row(children: [
          Container(width: 10, height: 10, color: Colors.green.shade700),
          const SizedBox(width: 6),
          const Text('Recettes', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 14),
          Container(width: 10, height: 10, color: Colors.red.shade700),
          const SizedBox(width: 6),
          const Text('Dépenses', style: TextStyle(fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _trend.map((r) {
              final rev = ((r['revenue'] as num?) ?? 0).toDouble();
              final exp = ((r['expenses'] as num?) ?? 0).toDouble();
              final revH = maxValue <= 0 ? 0.0 : (rev / maxValue) * 100;
              final expH = maxValue <= 0 ? 0.0 : (exp / maxValue) * 100;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(width: 8, height: revH < 1 ? 1 : revH, color: Colors.green.shade700),
                        const SizedBox(width: 3),
                        Container(width: 8, height: expH < 1 ? 1 : expH, color: Colors.red.shade700),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${r['label']}', style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _horizontalBars(List<Map<String, Object?>> rows, {required String labelKey, required String valueKey, required Color color, required bool isPercent}) {
    final shown = rows.take(8).toList();
    final maxValue = isPercent ? 100.0 : shown.fold<num>(1, (max, r) => ((r[valueKey] as num?) ?? 0) > max ? (r[valueKey] as num) : max);
    return Column(
      children: shown.map((r) {
        final raw = r[valueKey];
        final value = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
        final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 110, child: Text('${r[labelKey]}', style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: Stack(children: [
                  Container(height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3))),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 78,
                child: Text(
                  isPercent ? '${value.toStringAsFixed(1)} %' : formatXaf(value),
                  style: const TextStyle(fontSize: 10.5),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ReportTableScreen extends ConsumerWidget {
  const _ReportTableScreen({
    required this.title, required this.headers, required this.rows,
    this.scopeLabel = '', this.schoolYearLabel,
  });
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final String scopeLabel;
  final String? schoolYearLabel;

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    final establishment = await ref.read(establishmentProvider.future);
    final rawIdentity = await DocumentIdentity.fromEstablishment(establishment);
    final identity = schoolYearLabel == null ? rawIdentity
        : rawIdentity.forSchoolYear(schoolYearLabel!);
    final registry = DocumentNumberService();
    final reference = await registry.getOrCreate(type: 'RAP', entityId: '$title:${DateTime.now().microsecondsSinceEpoch}');
    final bytes = await ReportPdfService().table(
      title: title, headers: headers, rows: rows,
      identity: identity, reference: reference, subtitle: scopeLabel,
      pageFormat: headers.length >= 7 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    );
    await registry.recordFingerprint(reference: reference, bytes: bytes);
    await outputPdf(bytes, fileName: '${title.replaceAll(' ', '_')}_$reference.pdf');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(title), actions: [
          IconButton(tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: rows.isEmpty ? null : () => _exportPdf(context, ref)),
          IconButton(tooltip: 'Excel', icon: const Icon(Icons.table_view_outlined), onPressed: rows.isEmpty ? null : () async {final path=await ExcelExportService().export(fileName:title,headers:headers,rows:rows);if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Export Excel enregistré : $path'),duration:const Duration(seconds:5)));}),
        ]),
        body: rows.isEmpty ? const Center(child: Text('Aucune donnée')) : ResponsiveDataTable(headers: headers, rows: rows),
      );
}
