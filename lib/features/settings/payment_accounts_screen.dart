import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/settings_repository.dart';

class PaymentAccountsScreen extends ConsumerStatefulWidget {
  const PaymentAccountsScreen({super.key});

  @override
  ConsumerState<PaymentAccountsScreen> createState() => _PaymentAccountsScreenState();
}

class _PaymentAccountsScreenState extends ConsumerState<PaymentAccountsScreen> {
  List<PaymentMethodSetting> _methods = const [];
  List<CashAccountSetting> _accounts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final methods = await repo.paymentMethods();
      final accounts = await repo.cashAccounts();
      if (!mounted) return;
      setState(() {
        _methods = methods;
        _accounts = accounts;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _typeLabel(String type) => switch (type) {
        'cash' => 'Espèces / caisse physique',
        'mobile' => 'Mobile Money',
        'bank' => 'Banque / chèque',
        _ => type,
      };

  Future<void> _editMethod([PaymentMethodSetting? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    var type = item?.accountType ?? 'cash';
    var reference = item?.requiresReference ?? false;
    var active = item?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(item == null ? 'Nouveau moyen de paiement' : 'Modifier le moyen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type de compte compatible'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Espèces / caisse physique')),
                    DropdownMenuItem(value: 'mobile', child: Text('Mobile Money')),
                    DropdownMenuItem(value: 'bank', child: Text('Banque / chèque')),
                  ],
                  onChanged: (value) => setLocalState(() => type = value ?? type),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Référence obligatoire'),
                  subtitle: const Text('Ex. numéro de transaction ou référence bancaire'),
                  value: reference,
                  onChanged: (value) => setLocalState(() => reference = value),
                ),
                if (item != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    value: active,
                    onChanged: (value) => setLocalState(() => active = value),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    final value = name.text.trim();
    name.dispose();
    if (ok != true) return;
    try {
      await ref.read(settingsRepositoryProvider).savePaymentMethod(
            id: item?.id,
            name: value,
            accountType: type,
            requiresReference: reference,
            active: active,
          );
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _editAccount([CashAccountSetting? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final opening = TextEditingController(text: '${item?.openingBalance ?? 0}');
    var type = item?.type ?? 'cash';
    var active = item?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(item == null ? 'Nouvelle caisse / compte' : 'Modifier le compte'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom *')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Caisse physique')),
                    DropdownMenuItem(value: 'mobile', child: Text('Mobile Money')),
                    DropdownMenuItem(value: 'bank', child: Text('Compte bancaire')),
                  ],
                  onChanged: (value) => setLocalState(() => type = value ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: opening,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Solde initial'),
                ),
                if (item != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    value: active,
                    onChanged: (value) => setLocalState(() => active = value),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    final accountName = name.text.trim();
    final amount = int.tryParse(opening.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    name.dispose();
    opening.dispose();
    if (ok != true) return;
    try {
      await ref.read(settingsRepositoryProvider).saveCashAccount(
            id: item?.id,
            name: accountName,
            type: type,
            openingBalance: amount,
            active: active,
          );
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paiements & comptes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Moyens de paiement', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      FilledButton.tonalIcon(onPressed: () => _editMethod(), icon: const Icon(Icons.add), label: const Text('Ajouter')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._methods.map(
                    (m) => Card(
                      child: ListTile(
                        leading: Icon(m.active ? Icons.payments_outlined : Icons.block_outlined),
                        title: Text(m.name),
                        subtitle: Text('${_typeLabel(m.accountType)}${m.requiresReference ? ' · référence obligatoire' : ''}${m.active ? '' : ' · désactivé'}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editMethod(m),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Text('Caisses & comptes', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      FilledButton.tonalIcon(onPressed: () => _editAccount(), icon: const Icon(Icons.add), label: const Text('Ajouter')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._accounts.map(
                    (a) => Card(
                      child: ListTile(
                        leading: Icon(a.type == 'cash' ? Icons.point_of_sale_outlined : a.type == 'mobile' ? Icons.phone_android_outlined : Icons.account_balance_outlined),
                        title: Text(a.name),
                        subtitle: Text('${_typeLabel(a.type)} · solde initial ${formatXaf(a.openingBalance)}${a.active ? '' : ' · désactivé'}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editAccount(a),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
