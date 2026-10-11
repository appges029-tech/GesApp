import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/session/operator_session.dart';
import '../../data/models/student.dart';

class SimpleFeeSetupScreen extends ConsumerStatefulWidget {
  const SimpleFeeSetupScreen({super.key});
  @override
  ConsumerState<SimpleFeeSetupScreen> createState() => _SimpleFeeSetupScreenState();
}

class _SimpleFeeSetupScreenState extends ConsumerState<SimpleFeeSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _amount = TextEditingController();
  List<Map<String, Object?>> _cycles = const [];
  List<ClassroomOption> _classes = const [];
  String _frequency = 'mensuelle';
  String? _cycleId, _classId, _error;
  bool _byClass = false, _loading = true, _saving = false;
  DateTime _start = DateTime.now();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _name.dispose(); _amount.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final cycles = await ref.read(cyclesProvider.future);
      final classes = await ref.read(classroomsProvider.future);
      final school = await ref.read(establishmentProvider.future);
      if (!mounted) return;
      setState(() {
        _cycles = cycles; _classes = classes;
        _cycleId = cycles.isEmpty ? null : cycles.first['id'] as String;
        _classId = classes.isEmpty ? null : classes.first.id;
        _start = school?.schoolYearStart ?? DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false; _error = 'Chargement impossible : $e';
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !OperatorSession.hasPermission('finance.write')) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if ((_byClass ? _classId : _cycleId) == null) {
      setState(() => _error = 'Sélectionnez un cycle ou une classe.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(financeRepositoryProvider).createFeeWithTariff(
        name: _name.text,
        periodicity: _frequency,
        amount: int.parse(_amount.text.replaceAll(RegExp(r'\D'), '')),
        cycleId: _byClass ? null : _cycleId,
        classroomId: _byClass ? _classId : null,
        validFrom: _start,
      );
      ref.invalidate(feeCategoriesProvider);
      ref.invalidate(feeGridProvider);
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(auditEntriesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Frais et tarif créés. Les périodes sont automatiques.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = FriendlyError.message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _explanation => switch (_frequency) {
    'mensuelle' => 'Octobre à juin ; juillet en classe d’examen.',
    'trimestrielle' => 'Trois trimestres : T1, T2 et T3.',
    'annuelle' => 'Un paiement par année scolaire.',
    _ => 'Un paiement unique.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Créer des frais scolaires')),
    body: _loading ? const Center(child: CircularProgressIndicator()) :
      SafeArea(child: Form(key: _form, child: ListView(
        padding: const EdgeInsets.all(20), children: [
        const Text('Le nom, la fréquence, les élèves concernés et le montant suffisent.'),
        const SizedBox(height: 16),
        TextFormField(controller: _name,
          decoration: const InputDecoration(labelText: 'Nom des frais *',
            hintText: 'Ex. Frais de scolarité'),
          validator: (v) => v == null || v.trim().isEmpty ?
            'Indiquez le nom des frais.' : null),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _frequency, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Fréquence du paiement'),
          items: const [
            DropdownMenuItem(value: 'mensuelle', child: Text('Chaque mois')),
            DropdownMenuItem(value: 'trimestrielle', child: Text('Chaque trimestre')),
            DropdownMenuItem(value: 'annuelle', child: Text('Une fois par année')),
            DropdownMenuItem(value: 'unique', child: Text('Une seule fois')),
          ],
          onChanged: _saving ? null : (v) {
            if (v != null) setState(() => _frequency = v);
          }),
        const SizedBox(height: 6),
        Text(_explanation, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<bool>(
          initialValue: _byClass, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Appliquer les frais'),
          items: const [
            DropdownMenuItem(value: false, child: Text('À un cycle entier')),
            DropdownMenuItem(value: true, child: Text('À une classe précise')),
          ],
          onChanged: _saving ? null : (v) {
            if (v != null) setState(() => _byClass = v);
          }),
        const SizedBox(height: 12),
        if (!_byClass) DropdownButtonFormField<String>(
          key: const ValueKey('fee_cycle'), initialValue: _cycleId,
          isExpanded: true, decoration: const InputDecoration(labelText: 'Cycle *'),
          items: _cycles.map((c) => DropdownMenuItem<String>(
            value: c['id'] as String,
            child: Text((c['name'] ?? '').toString(),
              overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _saving ? null : (v) => setState(() => _cycleId = v),
        ) else DropdownButtonFormField<String>(
          key: const ValueKey('fee_class'), initialValue: _classId,
          isExpanded: true, decoration: const InputDecoration(labelText: 'Classe *'),
          items: _classes.map((c) => DropdownMenuItem<String>(
            value: c.id, child: Text(c.cycleName + ' · ' + c.name,
              overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _saving ? null : (v) => setState(() => _classId = v),
        ),
        const SizedBox(height: 16),
        TextFormField(controller: _amount, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Montant par période (FCFA) *'),
          validator: (v) => (int.tryParse(
            (v ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0) <= 0
              ? 'Entrez un montant positif.' : null),
        const SizedBox(height: 12),
        ListTile(contentPadding: EdgeInsets.zero,
          title: const Text('Tarif applicable à partir du'),
          subtitle: Text(_start.day.toString().padLeft(2, '0') + '/' +
            _start.month.toString().padLeft(2, '0') + '/' + _start.year.toString()),
          trailing: const Icon(Icons.calendar_month_outlined),
          onTap: _saving ? null : () async {
            final date = await showDatePicker(context: context,
              initialDate: _start, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (mounted && date != null) setState(() => _start = date);
          }),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _saving || !OperatorSession.hasPermission('finance.write')
          ? null : _save, icon: const Icon(Icons.check_circle_outline),
          label: Text(_saving ? 'Enregistrement…' : 'Créer les frais et le tarif')),
        const SizedBox(height: 12),
        const Text('Les paiements déjà enregistrés restent inchangés.'),
      ]))),
  );
