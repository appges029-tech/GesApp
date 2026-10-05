import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/sensitive_authorization_dialog.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../data/models/finance.dart';
import '../../services/receipt_printer.dart';
import '../../services/receipt_printing_preferences.dart';
import '../../services/receipt_service.dart';
import 'payment_form_screen.dart';

class PaymentsScreen extends ConsumerStatefulWidget{const PaymentsScreen({super.key});@override ConsumerState<PaymentsScreen> createState()=>_PaymentsScreenState();}
class _PaymentsScreenState extends ConsumerState<PaymentsScreen>{
  bool _showCancelled=false,_loading=false,_hasMore=true;int _offset=0;static const _page=75;final _query=TextEditingController();List<PaymentItem> _items=const[];
  @override void initState(){super.initState();_load(reset:true);}@override void dispose(){_query.dispose();super.dispose();}
  Future<void> _load({bool reset=false})async{if(_loading)return;if(reset){_offset=0;_items=const[];_hasMore=true;}if(!_hasMore)return;setState(()=>_loading=true);final rows=await ref.read(financeRepositoryProvider).searchPayments(query:_query.text,cancelled:_showCancelled,limit:_page,offset:_offset);if(mounted)setState((){_items=[..._items,...rows];_offset+=rows.length;_hasMore=rows.length==_page;_loading=false;});}
  Future<void> _reprint(PaymentItem item) async {
    final format = await showModalBottomSheet<ReceiptFormat>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Réimprimer ${item.receiptNumber}', style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Reçu A5'), subtitle: const Text('PDF administratif'), onTap: () => Navigator.pop(sheetContext, ReceiptFormat.a5)),
              ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Ticket POS 80 mm'), subtitle: const Text('Impression thermique directe'), onTap: () => Navigator.pop(sheetContext, ReceiptFormat.pos80)),
              ListTile(leading: const Icon(Icons.print_outlined), title: const Text('Ticket POS 58 mm'), subtitle: const Text('Petit rouleau thermique'), onTap: () => Navigator.pop(sheetContext, ReceiptFormat.pos58)),
            ],
          ),
        ),
      ),
    );
    if (format == null || !mounted) return;
    final establishment = await ref.read(establishmentProvider.future);
    final repo = ref.read(financeRepositoryProvider);
    final verification = await repo.verifyReceipt(item.receiptNumber);
    final lines = verification != null
        ? verification.lines.map((line) => ReceiptLine(label: line.label, amount: line.amount)).toList()
        : (await repo.paymentReceiptLines(item.receiptNumber))
            .map((r) => ReceiptLine(label: '${r['fee_name']} · ${r['period_key']}', amount: r['amount'] as int))
            .toList();
    final prefs = await ReceiptPrintingPreferencesStore().load();
    try {
      await ReceiptPrinter(ReceiptService()).printReceipt(
        establishment: establishment,
        receiptNumber: item.receiptNumber,
        beneficiaryName: item.studentName,
        amount: item.amount,
        paymentMethod: item.method,
        paidAt: item.paidAt,
        paymentReference: verification?.transactionReference ?? '',
        lines: lines,
        format: format,
        directToPrinter: format.isPos,
        printerUrl: prefs.printerUrl,
        showLogo: format.isPos ? prefs.showLogo : true,
        includeDetails: format.isPos ? prefs.includeDetails : true,
        copies: format.isPos ? prefs.copies : 1,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Impossible d'imprimer le reçu : $e")));
    }
  }
  Future<void> _cancel(PaymentItem item)async{final reason=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Annuler ce paiement ?'),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Reçu ${item.receiptNumber} · ${formatXaf(item.amount)}'),const SizedBox(height:10),TextField(controller:reason,decoration:const InputDecoration(labelText:"Motif de l'annulation *"))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Retour')),FilledButton(onPressed:()=>Navigator.pop(c,reason.text.trim().isNotEmpty),child:const Text('Confirmer'))]));final value=reason.text.trim();reason.dispose();if(ok!=true)return;final authorization=await requestSensitiveAuthorization(context:context,repository:ref.read(securityRepositoryProvider),action:'payment_cancel_authorization',entityId:item.id);if(authorization==null)return;try{await ref.read(financeRepositoryProvider).cancelPayment(paymentId:item.id,reason:value);await _load(reset:true);ref.invalidate(dashboardProvider);ref.invalidate(unpaidDuesProvider);ref.invalidate(auditEntriesProvider);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Erreur : $e')));}}
  Future<void> _refund(PaymentItem item) async {
    final repo = ref.read(financeRepositoryProvider);
    final remaining = await repo.refundableAmount(item.id);
    final methods = await repo.paymentMethods();
    final accounts = await repo.cashAccounts();
    if (!mounted) return;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce paiement est déjà entièrement remboursé.')),
      );
      return;
    }

    final amount = TextEditingController();
    final reason = TextEditingController();
    final reference = TextEditingController();
    String? method = methods.any((m) => m['name'] == item.method)
        ? item.method
        : (methods.isEmpty ? null : methods.first['name'] as String?);
    String? accountId;

    String? accountTypeForMethod(String? name) {
      for (final row in methods) {
        if (row['name'] == name) return row['account_type'] as String?;
      }
      return null;
    }

    List<Map<String, Object?>> compatibleAccounts(String? name) {
      final type = accountTypeForMethod(name);
      if (type == null) return accounts;
      return accounts.where((a) => a['type'] == type).toList();
    }

    final initialAccounts = compatibleAccounts(method);
    if (initialAccounts.isNotEmpty) accountId = initialAccounts.first['id'] as String;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          final availableAccounts = compatibleAccounts(method);
          if (accountId != null && !availableAccounts.any((a) => a['id'] == accountId)) {
            accountId = availableAccounts.isEmpty ? null : availableAccounts.first['id'] as String;
          }
          return AlertDialog(
            title: const Text('Remboursement partiel'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Remboursable : ${formatXaf(remaining)}'),
                  const SizedBox(height: 10),
                  TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant *')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Moyen de remboursement *'),
                    items: methods.map((m) => DropdownMenuItem(value: m['name'] as String, child: Text(m['name'] as String))).toList(),
                    onChanged: (value) => setDialogState(() {
                      method = value;
                      final compatible = compatibleAccounts(method);
                      accountId = compatible.isEmpty ? null : compatible.first['id'] as String;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Caisse / compte *'),
                    items: availableAccounts.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String))).toList(),
                    onChanged: (value) => setDialogState(() => accountId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: reference, decoration: const InputDecoration(labelText: 'Référence transaction / bordereau')),
                  const SizedBox(height: 10),
                  TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Motif *')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
              FilledButton(
                onPressed: () {
                  final value = int.tryParse(amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
                  Navigator.pop(c, value > 0 && value <= remaining && reason.text.trim().isNotEmpty && method != null && accountId != null);
                },
                child: const Text('Rembourser'),
              ),
            ],
          );
        },
      ),
    );

    final value = int.tryParse(amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final why = reason.text.trim();
    final refValue = reference.text.trim();
    amount.dispose();
    reason.dispose();
    reference.dispose();
    if (ok != true) return;
    final authorization = await requestSensitiveAuthorization(
      context: context,
      repository: ref.read(securityRepositoryProvider),
      action: 'payment_refund_authorization',
      entityId: item.id,
    );
    if (authorization == null) return;
    try {
      await repo.refundPayment(
        paymentId: item.id,
        amount: value,
        reason: why,
        paymentMethod: method,
        cashAccountId: accountId,
        transactionReference: refValue.isEmpty ? null : refValue,
      );
      await _load(reset: true);
      ref.invalidate(dashboardProvider);
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(auditEntriesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remboursement impossible : $e')));
      }
    }
  }

  Future<void> _newPayment() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentFormScreen()));
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = WindowsUi.isDesktop(context);
    final body = Column(
      children: [
        Padding(
          padding: desktop ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _query,
            onSubmitted: (_) => _load(reset: true),
            decoration: InputDecoration(
              labelText: 'Rechercher reçu, élève, famille, montant ou référence',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: () => _load(reset: true), icon: const Icon(Icons.arrow_forward)),
            ),
          ),
        ),
        if (_showCancelled) ...[
          SizedBox(height: desktop ? 10 : 0),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(desktop ? 8 : 0),
            ),
            padding: const EdgeInsets.all(8),
            child: const Text('Paiements annulés (contre-passés)', textAlign: TextAlign.center),
          ),
        ],
        SizedBox(height: desktop ? 12 : 0),
        Expanded(
          child: _items.isEmpty && !_loading
              ? Center(child: Text(_showCancelled ? 'Aucun paiement annulé.' : 'Aucun paiement enregistré.'))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: desktop
                      ? _PaymentsDesktopList(
                          items: _items,
                          loading: _loading,
                          hasMore: _hasMore,
                          showCancelled: _showCancelled,
                          onLoadMore: _load,
                          onPrint: _reprint,
                          onRefund: _refund,
                          onCancel: _cancel,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16).copyWith(bottom: 96),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            if (i == _items.length) {
                              return Center(
                                child: _loading
                                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                                    : OutlinedButton(onPressed: _load, child: const Text('Charger plus')),
                              );
                            }
                            final item = _items[i];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Icon(item.isFamilyPayment ? Icons.family_restroom : Icons.payments_outlined)),
                                title: Text(item.studentName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text(
                                  '${item.receiptNumber} · ${DateFormat('dd/MM/yyyy HH:mm').format(item.paidAt)} · ${item.method}'
                                  '${item.refundedAmount > 0 ? '\nRemboursé : ${formatXaf(item.refundedAmount)} · Net : ${formatXaf(item.amount - item.refundedAmount)}' : ''}'
                                  '${item.isCancelled && item.cancelReason != null ? '\nMotif : ${item.cancelReason}' : ''}',
                                ),
                                isThreeLine: item.refundedAmount > 0 || (item.isCancelled && item.cancelReason != null),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatXaf(item.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                                    if (!_showCancelled)
                                      PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'print') unawaited(_reprint(item));
                                          if (v == 'refund') unawaited(_refund(item));
                                          if (v == 'cancel') unawaited(_cancel(item));
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'print', child: Text('Réimprimer')),
                                          PopupMenuItem(value: 'refund', child: Text('Rembourser')),
                                          PopupMenuItem(value: 'cancel', child: Text('Annuler')),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
        if (_loading && _items.isNotEmpty) const LinearProgressIndicator(),
      ],
    );

    return WindowsPageScaffold(
      title: 'Encaissements',
      subtitle: desktop ? '${_items.length} paiement(s) chargé(s) · reçus, remboursements et annulations' : null,
      actions: [
        WindowsCommandButton(
          icon: _showCancelled ? Icons.receipt_long : Icons.history,
          label: _showCancelled ? 'Paiements actifs' : 'Paiements annulés',
          onPressed: () {
            setState(() => _showCancelled = !_showCancelled);
            _load(reset: true);
          },
        ),
        if (desktop && !_showCancelled) WindowsCommandButton(icon: Icons.add_card, label: 'Paiement', primary: true, onPressed: _newPayment),
      ],
      floatingActionButton: desktop || _showCancelled ? null : FloatingActionButton.extended(onPressed: _newPayment, icon: const Icon(Icons.add_card), label: const Text('Paiement')),
      body: body,
    );
  }
}

class _PaymentsDesktopList extends StatelessWidget {
  const _PaymentsDesktopList({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.showCancelled,
    required this.onLoadMore,
    required this.onPrint,
    required this.onRefund,
    required this.onCancel,
  });

  final List<PaymentItem> items;
  final bool loading;
  final bool hasMore;
  final bool showCancelled;
  final VoidCallback onLoadMore;
  final ValueChanged<PaymentItem> onPrint;
  final ValueChanged<PaymentItem> onRefund;
  final ValueChanged<PaymentItem> onCancel;

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
            color: scheme.surfaceContainerLow,
            child: const Row(children: [
              Expanded(flex: 3, child: _PaymentHeader('Bénéficiaire')),
              Expanded(flex: 2, child: _PaymentHeader('Reçu')),
              Expanded(flex: 2, child: _PaymentHeader('Date')),
              Expanded(flex: 2, child: _PaymentHeader('Moyen')),
              Expanded(flex: 2, child: _PaymentHeader('Montant')),
              Expanded(flex: 2, child: _PaymentHeader('Net')),
              SizedBox(width: 46),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .55)),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(child: loading ? const CircularProgressIndicator() : OutlinedButton(onPressed: onLoadMore, child: const Text('Charger plus'))),
                  );
                }
                final item = items[index];
                final net = item.amount - item.refundedAmount;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(item.studentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text(item.receiptNumber, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(DateFormat('dd/MM/yyyy HH:mm').format(item.paidAt), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(item.method, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(formatXaf(item.amount), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text(formatXaf(net), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 46,
                      child: showCancelled
                          ? const Icon(Icons.block_outlined, size: 18)
                          : PopupMenuButton<String>(
                              tooltip: 'Actions',
                              onSelected: (value) {
                                if (value == 'print') onPrint(item);
                                if (value == 'refund') onRefund(item);
                                if (value == 'cancel') onCancel(item);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'print', child: Text('Réimprimer')),
                                PopupMenuItem(value: 'refund', child: Text('Rembourser')),
                                PopupMenuItem(value: 'cancel', child: Text('Annuler')),
                              ],
                            ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentHeader extends StatelessWidget {
  const _PaymentHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700));
}
