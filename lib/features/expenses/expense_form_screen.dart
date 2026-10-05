import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../services/expense_proof_service.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _beneficiary = TextEditingController();
  final _reference = TextEditingController();

  String? _categoryId;
  String? _method;
  String? _accountId;
  List<Map<String, Object?>> _methods = const [];
  List<Map<String, Object?>> _accounts = const [];
  DateTime _spentAt = DateTime.now();
  String? _proofPath;
  bool _saving = false;
  bool _loadingConfig = true;
  bool _persisted = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadConfiguration);
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _beneficiary.dispose();
    _reference.dispose();
    final proof = _proofPath;
    if (!_persisted && proof != null) {
      ExpenseProofService().delete(proof);
    }
    super.dispose();
  }

  Future<void> _loadConfiguration() async {
    try {
      final finance = ref.read(financeRepositoryProvider);
      final methods = await finance.paymentMethods();
      final accounts = await finance.cashAccounts();
      if (!mounted) return;
      setState(() {
        _methods = methods;
        _accounts = accounts;
        if (methods.isNotEmpty) _method = methods.first['name'] as String;
        _accountId = _compatibleAccount(_method);
        _loadingConfig = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  Map<String, Object?>? _methodRow(String? name) {
    if (name == null) return null;
    for (final row in _methods) {
      if ((row['name'] as String).toLowerCase() == name.toLowerCase()) return row;
    }
    return null;
  }

  String? _compatibleAccount(String? method, {String? current}) {
    final type = (_methodRow(method)?['account_type'] as String?) ?? 'cash';
    final compatible = _accounts.where((a) => a['type'] == type).toList();
    if (compatible.isEmpty) return null;
    if (current != null && compatible.any((a) => a['id'] == current)) return current;
    return compatible.first['id'] as String;
  }

  bool get _referenceRequired => (_methodRow(_method)?['requires_reference'] as int? ?? 0) == 1;
  String get _accountType => (_methodRow(_method)?['account_type'] as String?) ?? 'cash';

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _spentAt,
    );
    if (value != null && mounted) setState(() => _spentAt = value);
  }

  Future<void> _pickProof() async {
    final previous = _proofPath;
    final value = await ExpenseProofService().pickAndStore('draft_${DateTime.now().millisecondsSinceEpoch}');
    if (value == null || !mounted) return;
    setState(() => _proofPath = value);
    if (previous != null && previous != value) await ExpenseProofService().delete(previous);
  }

  Future<void> _removeProof() async {
    final value = _proofPath;
    if (value == null) return;
    setState(() => _proofPath = null);
    await ExpenseProofService().delete(value);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate() || _categoryId == null || _method == null || _accountId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(expenseRepositoryProvider).submitForApproval(
            categoryId: _categoryId!,
            amount: int.parse(_amount.text.replaceAll(RegExp(r'\D'), '')),
            description: _description.text,
            spentAt: _spentAt,
            beneficiary: _beneficiary.text,
            paymentMethod: _method,
            cashAccountId: _accountId,
            externalReference: _reference.text,
            proofPath: _proofPath,
          );
      _persisted = true;
      ref.invalidate(expensesProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _newCategory() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle catégorie'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nom')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim().isNotEmpty), child: const Text('Créer')),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (ok != true) return;
    final category = await ref.read(expenseRepositoryProvider).addCategory(name);
    ref.invalidate(expenseCategoriesProvider);
    if (mounted) setState(() => _categoryId = category.id);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle dépense')),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            categories.when(
              data: (items) => Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(labelText: 'Catégorie *'),
                      items: items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                      onChanged: (value) => setState(() => _categoryId = value),
                      validator: (value) => value == null ? 'Catégorie obligatoire' : null,
                    ),
                  ),
                  IconButton(onPressed: _newCategory, icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('$error'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Montant *'),
              validator: (value) => (int.tryParse((value ?? '').replaceAll(RegExp(r'\D'), '')) ?? 0) <= 0 ? 'Montant invalide' : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month),
              title: const Text('Date réelle de la dépense'),
              subtitle: Text(_spentAt.toIso8601String().split('T').first),
              onTap: _pickDate,
            ),
            TextFormField(controller: _beneficiary, decoration: const InputDecoration(labelText: 'Fournisseur / bénéficiaire')),
            const SizedBox(height: 12),
            if (_loadingConfig)
              const LinearProgressIndicator()
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _methods.any((m) => m['name'] == _method) ? _method : null,
                decoration: const InputDecoration(labelText: 'Moyen de paiement *'),
                items: _methods.map((m) => DropdownMenuItem(value: m['name'] as String, child: Text(m['name'] as String))).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _method = value;
                    _accountId = _compatibleAccount(value, current: _accountId);
                  });
                },
                validator: (value) => value == null ? 'Moyen obligatoire' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accounts.any((a) => a['id'] == _accountId && a['type'] == _accountType) ? _accountId : null,
                decoration: const InputDecoration(labelText: 'Caisse / compte *'),
                items: _accounts
                    .where((a) => a['type'] == _accountType)
                    .map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String)))
                    .toList(),
                onChanged: (value) => setState(() => _accountId = value),
                validator: (value) => value == null ? 'Caisse / compte obligatoire' : null,
              ),
            ],
            const SizedBox(height: 12),
            if (_referenceRequired)
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'Référence externe *'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Référence obligatoire' : null,
              )
            else
              TextFormField(controller: _reference, decoration: const InputDecoration(labelText: 'Référence externe (facultative)')),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(_proofPath == null ? Icons.attach_file : Icons.verified_outlined),
                title: Text(_proofPath == null ? 'Ajouter un justificatif' : 'Justificatif joint'),
                subtitle: const Text('PDF, JPG, PNG ou WebP · conservé dans la sauvegarde'),
                onTap: _pickProof,
                trailing: _proofPath == null ? null : IconButton(onPressed: _removeProof, icon: const Icon(Icons.delete_outline)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Enregistrement…' : 'Soumettre la dépense'),
            ),
          ],
        ),
      ),
    );
  }
}
