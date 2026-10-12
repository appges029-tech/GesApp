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

/// Génère les appels à paiement des élèves d'une classe ("salle") d'un cycle,
/// pour un mois précis, sous forme de PDF A4 avec 8 avis par page.
class PaymentNoticesScreen extends ConsumerStatefulWidget {
  const PaymentNoticesScreen({super.key});
  @override
  ConsumerState<PaymentNoticesScreen> createState() => _PaymentNoticesScreenState();
}

class _PaymentNoticesScreenState extends ConsumerState<PaymentNoticesScreen> {
  String? _schoolYearId;
  String? _cycleId;
  String? _classroomId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _loading = false;
  List<StudentNoticeData> _preview = const [];

  String get _periodKey => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  String get _periodLabel {
    const mois = ['janvier','février','mars','avril','mai','juin','juillet','août','septembre','octobre','novembre','décembre'];
    return '${mois[_month.month - 1]} ${_month.year}';
  }

  Future<void> _pickMonth() async {
    final v = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _month,
      helpText: 'Choisir un mois',
    );
    if (v != null && mounted) setState(() => _month = DateTime(v.year, v.month, 1));
  }

  Future<void> _loadPreview() async {
    if (_classroomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez sélectionner une classe / salle.')));
      return;
    }
    setState(() { _loading = true; _preview = const []; });
    try {
      final filter = ReportFilter(
        cycleId: _cycleId,
        classroomId: _classroomId,
        schoolYearId: _schoolYearId,
        periodKey: _periodKey,
      );
      final rows = await ref.read(reportRepositoryProvider).billingDues(filter: filter);
      final grouped = groupDuesByStudent(rows);
      if (!mounted) return;
      setState(() => _preview = grouped);
      if (grouped.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune échéance trouvée pour ces filtres.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generatePdf() async {
    // Les dettes sont relues au moment de la génération, même après un aperçu.
    // Un paiement enregistré entre-temps ne doit jamais laisser un appel périmé.
    await _loadPreview();
    if (!mounted || _preview.isEmpty) return;
    setState(() => _loading = true);
    try {
      final establishment = await ref.read(establishmentProvider.future);
      final cycles = await ref.read(cyclesProvider.future);
      final classrooms = await ref.read(classroomsProvider.future);
      final years = await ref.read(schoolYearsProvider.future);
      final schoolYearLabel = resolvePaymentNoticeSchoolYearLabel(
        years: years,
        selectedSchoolYearId: _schoolYearId,
        establishmentLabel: establishment?.schoolYearLabel,
      );
      final cycleLabel = cycles.firstWhere((c) => c['id'] == _cycleId, orElse: () => const {})['name'] as String?;
      final matchingClassrooms = classrooms.where((c) => c.id == _classroomId).toList();
      final classroomLabel = matchingClassrooms.isEmpty ? null : matchingClassrooms.first.name;
      final logoPath = establishment?.logoPath;
      final logoBytes = (logoPath == null || logoPath.isEmpty) ? null : await StudentMediaService().readStoredFileBytes(logoPath);
      final registry = DocumentNumberService();
      final reference = await registry.getOrCreate(type: 'APP', entityId: '${_classroomId ?? ''}:$_periodKey:${DateTime.now().microsecondsSinceEpoch}');
      final bytes = await PaymentNoticeBatchPdfService().build(
        students: _preview,
        periodLabel: _periodLabel,
        establishmentName: establishment?.name,
        establishmentAddress: establishment?.address,
        establishmentPhone: establishment?.phone,
        establishmentEmail: establishment?.email,
        approvalNumber: establishment?.approvalNumber,
        schoolYearLabel: schoolYearLabel,
        batchReference: reference,
        cycleLabel: cycleLabel,
        classroomLabel: classroomLabel,
        logoBytes: logoBytes,
      );
      await registry.recordFingerprint(reference: reference, bytes: bytes);
      await outputPdf(bytes, fileName: 'Appels_paiement_${classroomLabel ?? ''}_${_periodKey}_$reference.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Génération impossible : $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycles = ref.watch(cyclesProvider);
    final classrooms = ref.watch(classroomsProvider);
    final years = ref.watch(schoolYearsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Appels à paiement (par classe)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filtres', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  years.when(
                    data: (items) => DropdownButtonFormField<String>(
                      initialValue: _schoolYearId,
                      decoration: const InputDecoration(labelText: 'Année scolaire'),
                      hint: const Text('Année active'),
                      items: items.map((y) => DropdownMenuItem(value: y.id, child: Text('${y.label}${y.isActive ? ' · active' : ''}'))).toList(),
                      onChanged: (v) => setState(() { _schoolYearId = v; _preview = const []; }),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e'),
                  ),
                  const SizedBox(height: 10),
                  cycles.when(
                    data: (items) => DropdownButtonFormField<String>(
                      initialValue: _cycleId,
                      decoration: const InputDecoration(labelText: 'Cycle'),
                      items: items.map((r) => DropdownMenuItem(value: r['id'] as String, child: Text(r['name'] as String))).toList(),
                      onChanged: (v) => setState(() { _cycleId = v; _classroomId = null; _preview = const []; }),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e'),
                  ),
                  const SizedBox(height: 10),
                  classrooms.when(
                    data: (items) {
                      final shown = _cycleId == null ? items : items.where((c) => c.cycleId == _cycleId).toList();
                      return DropdownButtonFormField<String>(
                        initialValue: shown.any((c) => c.id == _classroomId) ? _classroomId : null,
                        decoration: const InputDecoration(labelText: 'Classe / Salle *'),
                        items: shown.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.cycleName} · ${c.name}'))).toList(),
                        onChanged: (v) => setState(() { _classroomId = v; _preview = const []; }),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async { await _pickMonth(); setState(() => _preview = const []); },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text('Mois : $_periodLabel'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _loadPreview,
                          icon: const Icon(Icons.search),
                          label: const Text('Aperçu'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _generatePdf,
                          icon: _loading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Générer les appels (PDF)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_preview.isNotEmpty) ...[
            Text('${_preview.length} élève(s) avec une échéance sur $_periodLabel — 8 appels à paiement par page A4.', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._preview.map((s) => Card(
                  child: ListTile(
                    title: Text(s.studentName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${s.registrationNumber} · ${s.cycle} / ${s.classroom}\nReste à payer : ${formatXaf(s.totalBalance)}'),
                    isThreeLine: true,
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
