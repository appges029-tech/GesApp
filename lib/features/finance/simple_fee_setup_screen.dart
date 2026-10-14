import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/session/operator_session.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/models/student.dart';

/// Single, explicit workflow for new or existing fees and multiple targets.
class SimpleFeeSetupScreen extends ConsumerStatefulWidget {
  const SimpleFeeSetupScreen({super.key});
  @override
  ConsumerState<SimpleFeeSetupScreen> createState() => _SimpleFeeSetupScreenState();
}

class _SimpleFeeSetupScreenState extends ConsumerState<SimpleFeeSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  List<Map<String, Object?>> _cycles = const [];
  List<ClassroomOption> _classes = const [];
  List<FeeCategoryItem> _fees = const [];
  final Set<String> _targets = {};
  String _frequency = 'mensuelle';
  String? _existingFeeId, _error;
  bool _useExisting = false, _byClass = false, _loading = true, _saving = false;
  DateTime _start = DateTime.now();

  FeeCategoryItem? get _chosenFee {
    for (final fee in _fees) {
      if (fee.id == _existingFeeId) return fee;
    }
    return null;
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cycles = await ref.read(cyclesProvider.future);
      final classes = await ref.read(classroomsProvider.future);
      final fees = await ref.read(feeCategoriesProvider.future);
      final school = await ref.read(establishmentProvider.future);
      if (!mounted) return;
      setState(() {
        _cycles = cycles;
        _classes = classes;
        _fees = fees;
        _start = school?.schoolYearStart ?? DateTime.now();
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = 'Impossible de charger la configuration : ' +
            FriendlyError.message(error);
        _loading = false;
      });
    }
  }

  String get _description => switch (_frequency) {
    'mensuelle' => 'Octobre à juin, plus juillet pour les classes d’examen.',
    'trimestrielle' => 'Trois paiements : T1, T2 et T3.',
    'annuelle' => 'Une fois par année scolaire.',
    _ => 'Un paiement unique.',
  };

  List<String> get _targetLabels => _byClass
      ? _classes.where((c) => _targets.contains(c.id))
          .map((c) => c.cycleName + ' · ' + c.name).toList()
      : _cycles.where((c) => _targets.contains(c['id']))
          .map((c) => (c['name'] ?? '').toString()).toList();

  Future<void> _save() async {
    if (_saving || !OperatorSession.hasPermission('finance.write')) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_useExisting && _chosenFee == null) {
      setState(() => _error = 'Sélectionnez une rubrique existante.');
      return;
    }
    if (_targets.isEmpty) {
      setState(() => _error = 'Cochez au moins une classe ou un cycle.');
      return;
    }
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    final feeName = _useExisting ? _chosenFee!.name : _name.text.trim();
    final targetLabels = _targetLabels;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vérifier les frais avant création'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rubrique : ' + feeName),
            Text('Fréquence : ' + _description),
            Text('Montant par période : ' + formatXaf(amount)),
            const SizedBox(height: 8),
            Text('Tarifs à ajouter : ' + targetLabels.length.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
            ...targetLabels.map((label) => Text('• ' + label)),
            const SizedBox(height: 8),
            const Text('Les tarifs déjà enregistrés ne seront pas remplacés.'),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Modifier')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer la création')),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(financeRepositoryProvider).configureFeeForTargets(
        existingFeeId: _useExisting ? _existingFeeId : null,
        name: feeName,
        periodicity: _frequency,
        amount: amount,
        cycleIds: _byClass ? const [] : _targets.toList(),
        classroomIds: _byClass ? _targets.toList() : const [],
        validFrom: _start,
      );
    } catch (error) {
      if (mounted) setState(() {
        _error = FriendlyError.message(error);
        _saving = false;
      });
      return;
    }
    try {
      ref.invalidate(feeCategoriesProvider);
      ref.invalidate(feeGridProvider);
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (_) {
      // The fee transaction is already committed.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Frais et tarifs enregistrés pour les groupes choisis.')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Créer des frais scolaires')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Définissez une fois les frais, puis choisissez les '
              'classes ou cycles concernés. Aucun échéancier manuel.'),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Utiliser une rubrique existante'),
              subtitle: const Text('Ajouter ses frais à d’autres classes ou cycles'),
              value: _useExisting,
              onChanged: _saving ? null : (value) => setState(() {
                _useExisting = value;
                _existingFeeId = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_useExisting)
              DropdownButtonFormField<String>(
                key: const ValueKey('existing_fee'),
                initialValue: _existingFeeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Rubrique existante *'),
                items: _fees.map((fee) => DropdownMenuItem(
                  value: fee.id, child: Text(fee.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _saving ? null : (value) => setState(() {
                  _existingFeeId = value;
                  _frequency = _chosenFee?.periodicity ?? 'mensuelle';
                }),
              )
            else
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom des frais *', hintText: 'Ex. Frais de scolarité'),
                validator: (value) => _useExisting || (value ?? '').trim().isNotEmpty
                    ? null : 'Donnez un nom aux frais.',
              ),
            const SizedBox(height: 12),
            if (_useExisting)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fréquence définie par la rubrique'),
                subtitle: Text(_description),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Fréquence des paiements'),
                items: const [
                  DropdownMenuItem(value: 'mensuelle', child: Text('Chaque mois')),
                  DropdownMenuItem(value: 'trimestrielle', child: Text('Chaque trimestre')),
                  DropdownMenuItem(value: 'annuelle', child: Text('Une fois par année')),
                  DropdownMenuItem(value: 'unique', child: Text('Une seule fois')),
                ],
                onChanged: _saving ? null : (value) {
                  if (value != null) setState(() => _frequency = value);
                },
              ),
            if (!_useExisting) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_description,
                style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 20),
            DropdownButtonFormField<bool>(
              initialValue: _byClass,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Appliquer les frais à'),
              items: const [
                DropdownMenuItem(value: false, child: Text('Un ou plusieurs cycles')),
                DropdownMenuItem(value: true, child: Text('Une ou plusieurs classes')),
              ],
              onChanged: _saving ? null : (value) {
                if (value != null) setState(() {
                  _byClass = value;
                  _targets.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            Text('Sélectionnez les groupes concernés',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (_byClass)
                for (final c in _classes)
                  FilterChip(
                    label: Text(c.cycleName + ' · ' + c.name),
                    selected: _targets.contains(c.id),
                    onSelected: _saving ? null : (v) => setState(() {
                      if (v) { _targets.add(c.id); } else { _targets.remove(c.id); }
                    }),
                  )
              else
                for (final c in _cycles)
                  FilterChip(
                    label: Text((c['name'] ?? '').toString()),
                    selected: _targets.contains(c['id']),
                    onSelected: _saving ? null : (v) => setState(() {
                      final id = c['id'] as String;
                      if (v) { _targets.add(id); } else { _targets.remove(id); }
                    }),
                  ),
            ]),
            const SizedBox(height: 8),
            Text(_targets.isEmpty
                ? 'Aucun groupe sélectionné.'
                : _targets.length.toString() + ' groupe(s) sélectionné(s).'),
            const SizedBox(height: 18),
            TextFormField(
              controller: _amount, keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Montant par période (FCFA) *'),
              validator: (value) {
                final n = int.tryParse((value ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0;
                return n > 0 ? null : 'Entrez un montant positif.';
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tarif applicable à partir du'),
              subtitle: Text(_start.day.toString().padLeft(2, '0') + '/' +
                _start.month.toString().padLeft(2, '0') + '/' + _start.year.toString()),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _saving ? null : () async {
                final next = await showDatePicker(context: context,
                  initialDate: _start, firstDate: DateTime(2020),
                  lastDate: DateTime(2100));
                if (mounted && next != null) setState(() => _start = next);
              },
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving || !OperatorSession.hasPermission('finance.write')
                ? null : _save,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(_saving ? 'Enregistrement…' : 'Vérifier et enregistrer'),
            ),
          ]),
        )),
  );
}
