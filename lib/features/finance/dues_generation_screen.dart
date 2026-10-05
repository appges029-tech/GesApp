import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance_full.dart';

class DuesGenerationScreen extends ConsumerStatefulWidget {
  const DuesGenerationScreen({super.key});

  @override
  ConsumerState<DuesGenerationScreen> createState() => _DuesGenerationScreenState();
}

class _DuesGenerationScreenState extends ConsumerState<DuesGenerationScreen> {
  String _periodicity = 'mensuelle';
  DateTime _referenceMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _year = DateTime.now().month >= 9 ? DateTime.now().year : DateTime.now().year - 1;
  int _trimester = 1;
  DateTime _dueDate = DateTime.now();
  bool _busy = false;
  String? _resultMessage;
  DueGenerationPreview? _preview;
  List<BillingBatchItem> _batches = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _loadSchoolYearDefaults();
      await _loadBatches();
    });
  }

  Future<void> _loadSchoolYearDefaults() async {
    try {
      final establishment = await ref.read(establishmentProvider.future);
      if (!mounted || establishment == null) return;
      setState(() {
        _year = establishment.schoolYearStart.year;
        _referenceMonth = DateTime(establishment.schoolYearStart.year, establishment.schoolYearStart.month, 1);
        _dueDate = establishment.schoolYearStart;
      });
    } catch (_) {}
  }

  Future<void> _loadBatches() async {
    try {
      final rows = await ref.read(financeRepositoryProvider).billingBatches();
      if (mounted) setState(() => _batches = rows);
    } catch (_) {}
  }

  String get _periodKey {
    switch (_periodicity) {
      case 'mensuelle':
        return '${_referenceMonth.year}-${_referenceMonth.month.toString().padLeft(2, '0')}';
      case 'trimestrielle':
        return '$_year-T$_trimester';
      case 'annuelle':
        return '$_year-annuel';
      default:
        return '$_year-unique';
    }
  }

  Future<DateTime> _billingReferenceDate() async {
    if (_periodicity == 'mensuelle') return DateTime(_referenceMonth.year, _referenceMonth.month, 1);
    final establishment = await ref.read(establishmentProvider.future);
    final startMonth = establishment?.schoolYearStart.month ?? 10;
    final startDay = establishment?.schoolYearStart.day ?? 1;
    if (_periodicity == 'trimestrielle') {
      return DateTime(_year, startMonth + ((_trimester - 1) * 3), startDay);
    }
    return DateTime(_year, startMonth, startDay);
  }

  Future<void> _simulate() async {
    setState(() {
      _busy = true;
      _resultMessage = null;
      _preview = null;
    });
    try {
      final reference = await _billingReferenceDate();
      final preview = await ref.read(financeRepositoryProvider).previewDues(
            periodKey: _periodKey,
            periodicity: _periodicity,
            dueDate: _dueDate,
            referenceDate: reference,
          );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) setState(() => _resultMessage = 'Erreur : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    if (_preview == null) {
      await _simulate();
      if (_preview == null) return;
    }
    if (_preview!.candidateCount == 0) {
      setState(() => _resultMessage = 'Aucune nouvelle échéance à créer.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer la génération'),
        content: Text(
          '${_preview!.candidateCount} échéance(s) seront créées pour un total de ${formatXaf(_preview!.totalAmount)}.\n\n'
          'Un lot de facturation sera créé et pourra être annulé tant qu’aucun règlement ne l’a touché.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Générer')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final reference = await _billingReferenceDate();
      final created = await ref.read(financeRepositoryProvider).generateDues(
            periodKey: _periodKey,
            periodicity: _periodicity,
            dueDate: _dueDate,
            referenceDate: reference,
          );
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(auditEntriesProvider);
      await _loadBatches();
      if (!mounted) return;
      setState(() {
        _preview = null;
        _resultMessage = created == 0
            ? 'Aucune échéance nouvelle créée.'
            : '$created échéance(s) créées dans un lot de facturation pour « $_periodKey ».';
      });
    } catch (error) {
      if (mounted) setState(() => _resultMessage = 'Erreur : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelBatch(BillingBatchItem batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler le lot ?'),
        content: Text('Supprimer les ${batch.generatedCount} échéance(s) du lot ${batch.periodKey} ? Cette action est refusée si un paiement ou un avoir a déjà été appliqué.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Annuler le lot')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(financeRepositoryProvider).cancelBillingBatch(batch.id);
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(auditEntriesProvider);
      await _loadBatches();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lot annulé proprement.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _resetPreview() {
    if (_preview != null) setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Génération des échéances')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.preview_outlined),
              title: Text('Simulation obligatoire avant génération'),
              subtitle: Text('GesApp calcule le nombre d’élèves, les échéances nouvelles et le total avant toute écriture.'),
            ),
          ),
          const SizedBox(height: 12),
          Text('Périodicité', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mensuelle', label: Text('Mensuelle')),
                ButtonSegment(value: 'trimestrielle', label: Text('Trimestrielle')),
                ButtonSegment(value: 'annuelle', label: Text('Annuelle')),
                ButtonSegment(value: 'unique', label: Text('Unique')),
              ],
              selected: {_periodicity},
              onSelectionChanged: (value) {
                setState(() => _periodicity = value.first);
                _resetPreview();
              },
            ),
          ),
          const SizedBox(height: 20),
          if (_periodicity == 'mensuelle')
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Mois : ${_referenceMonth.month.toString().padLeft(2, '0')}/${_referenceMonth.year}'),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _referenceMonth, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (picked != null && mounted) {
                  setState(() {
                    _referenceMonth = DateTime(picked.year, picked.month, 1);
                    _preview = null;
                  });
                }
              },
            )
          else if (_periodicity == 'trimestrielle')
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _trimester,
                    decoration: const InputDecoration(labelText: 'Trimestre'),
                    items: const [1, 2, 3].map((t) => DropdownMenuItem(value: t, child: Text('Trimestre $t'))).toList(),
                    onChanged: (value) => setState(() {
                      _trimester = value ?? 1;
                      _preview = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: '$_year',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Année de début'),
                    onChanged: (value) {
                      _year = int.tryParse(value) ?? _year;
                      _resetPreview();
                    },
                  ),
                ),
              ],
            )
          else
            TextFormField(
              initialValue: '$_year',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Année de début'),
              onChanged: (value) {
                _year = int.tryParse(value) ?? _year;
                _resetPreview();
              },
            ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date limite : ${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}'),
            trailing: const Icon(Icons.event_outlined),
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _dueDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked != null && mounted) {
                setState(() {
                  _dueDate = picked;
                  _preview = null;
                });
              }
            },
          ),
          Text('Clé de période : $_periodKey', style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _simulate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Simuler avant génération'),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Simulation · ${_preview!.schoolYearLabel}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Élèves examinés : ${_preview!.studentCount}'),
                    Text('Nouvelles échéances : ${_preview!.candidateCount}'),
                    Text('Déjà existantes / ignorées : ${_preview!.alreadyExistingCount}'),
                    Text('Total à facturer : ${formatXaf(_preview!.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _preview == null ? null : _generate,
            icon: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined),
            label: Text(_busy ? 'Traitement…' : 'Confirmer et créer le lot'),
          ),
          if (_resultMessage != null) ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_resultMessage!))),
          ],
          const SizedBox(height: 28),
          Text('Lots récents', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_batches.isEmpty)
            const Text('Aucun lot de facturation enregistré.')
          else
            ..._batches.map(
              (batch) => Card(
                child: ListTile(
                  leading: Icon(batch.status == 'posted' ? Icons.inventory_2_outlined : Icons.cancel_outlined),
                  title: Text('${batch.periodKey} · ${batch.schoolYearLabel}'),
                  subtitle: Text('${batch.generatedCount} échéance(s) · ${formatXaf(batch.totalAmount)} · ${batch.status == 'posted' ? 'actif' : 'annulé'}'),
                  trailing: batch.canCancel && !OperatorSession.isAdmin
                      ? IconButton(tooltip: 'Annuler le lot', onPressed: () => _cancelBatch(batch), icon: const Icon(Icons.undo_outlined))
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
