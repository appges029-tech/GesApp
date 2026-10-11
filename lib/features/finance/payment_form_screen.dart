import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/windows/windows_page_scaffold.dart';
import '../../core/windows/windows_panels.dart';
import '../../core/windows/windows_ui.dart';
import '../../services/receipt_printer.dart';
import '../../services/receipt_printing_preferences.dart';
import '../../services/receipt_service.dart';
import '../../data/models/finance_full.dart';
import '../../data/models/student.dart';
import '../../data/models/family.dart';

enum _PayerType { student, family }

class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({super.key});

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  _PayerType _payerType = _PayerType.student;
  String? _studentId;
  String? _familyId;
  String? _cycleId;
  String? _classroomId;
  String? _feeId;
  String _method = 'Espèces';
  String? _cashAccountId = 'main_cash';
  List<Map<String, Object?>> _paymentMethods = const [];
  List<Map<String, Object?>> _cashAccounts = const [];
  bool _loadingPaymentConfig = true;
  final _reference = TextEditingController();
  final _payerPhone = TextEditingController();
  final _operator = TextEditingController();
  List<DueItem> _payerDues = const [];
  final Set<String> _selectedDues = {};
  bool _saving = false;
  bool _loadingBalance = false;
  int? _outstanding;
  int _credit = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPaymentConfiguration);
  }

  Future<void> _loadPaymentConfiguration() async {
    try {
      final repo = ref.read(financeRepositoryProvider);
      final methods = await repo.paymentMethods();
      final accounts = await repo.cashAccounts();
      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        _cashAccounts = accounts;
        if (methods.isNotEmpty && !methods.any((m) => m['name'] == _method)) {
          _method = methods.first['name'] as String;
        }
        _cashAccountId = _compatibleAccountId(_method, current: _cashAccountId);
        _loadingPaymentConfig = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPaymentConfig = false);
    }
  }

  Map<String, Object?>? _methodRow(String name) {
    for (final row in _paymentMethods) {
      if ((row['name'] as String).toLowerCase() == name.toLowerCase()) return row;
    }
    return null;
  }

  String? _compatibleAccountId(String method, {String? current}) {
    final expected = (_methodRow(method)?['account_type'] as String?) ?? 'cash';
    final compatible = _cashAccounts.where((a) => a['type'] == expected).toList();
    if (compatible.isEmpty) return null;
    if (current != null && compatible.any((a) => a['id'] == current)) return current;
    return compatible.first['id'] as String;
  }

  bool get _referenceRequired => (_methodRow(_method)?['requires_reference'] as int? ?? 0) == 1;
  String get _methodAccountType => (_methodRow(_method)?['account_type'] as String?) ?? 'cash';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose(); _reference.dispose(); _payerPhone.dispose(); _operator.dispose();
    super.dispose();
  }


  String _periodLabel(DueItem due) {
    final key = due.periodKey;
    final parts = key.split('-');
    if (parts.length == 2 && parts[0].length == 4) {
      final month = int.tryParse(parts[1]);
      if (month != null && month >= 1 && month <= 12) {
        const months = [
          'Janvier','Février','Mars','Avril','Mai','Juin',
          'Juillet','Août','Septembre','Octobre','Novembre','Décembre'
        ];
        return months[month - 1] + ' ' + parts[0];
      }
    }
    if (key.contains('-T')) return key.replaceAll('-T', ' · Trimestre ');
    return key;
  }

  String _periodDeadline(DueItem due) {
    if (due.dueDate == null) return '';
    final d = due.dueDate!;
    return ' · Limite : ' + d.day.toString().padLeft(2, '0') + '/' +
        d.month.toString().padLeft(2, '0') + '/' + d.year.toString();
  }

  int get _selectedRemaining => _payerDues
      .where((due) => _selectedDues.contains(due.id))
      .fold<int>(0, (total, due) => total + due.balance);

  void _chooseRubric(String? feeId) {
    setState(() {
      _feeId = feeId;
      _selectedDues.clear();
      for (final due in _payerDues) {
        if (due.feeId == feeId && due.balance > 0) {
          _selectedDues.add(due.id);
          break;
        }
      }
      _amount.text = _selectedRemaining > 0 ? _selectedRemaining.toString() : '';
    });
  }

  void _chooseDue(DueItem due, bool selected) {
    if (due.balance <= 0 || due.feeId != _feeId) return;
    setState(() {
      if (selected) { _selectedDues.add(due.id); }
      else { _selectedDues.remove(due.id); }
      _amount.text = _selectedRemaining > 0 ? _selectedRemaining.toString() : '';
    });
  }

  void _chooseDueFamily(DueItem due, bool selected) {
    setState(() {
      if (selected) { _selectedDues.add(due.id); }
      else { _selectedDues.remove(due.id); }
      _amount.text = _selectedRemaining > 0 ? _selectedRemaining.toString() : '';
    });
  }

  Future<void> _loadOutstanding() async {
    final studentId = _studentId;
    final familyId = _familyId;
    final payerType = _payerType;
    if ((_payerType == _PayerType.student && studentId == null) ||
        (_payerType == _PayerType.family && familyId == null)) {
      if (mounted) setState(() {
        _outstanding = null;
        _credit = 0;
        _payerDues = const [];
        _selectedDues.clear();
        _feeId = null;
        _amount.clear();
      });
      return;
    }
    setState(() => _loadingBalance = true);
    try {
      final repo = ref.read(financeRepositoryProvider);
      if (payerType == _PayerType.student) {
        await repo.ensureAutomaticDuesForStudent(studentId!);
      } else {
        await repo.ensureAutomaticDuesForFamily(familyId!);
      }
      final value = _payerType == _PayerType.student
          ? await repo.outstandingForStudent(studentId!)
          : await repo.outstandingForFamily(familyId!);
      final dues = await repo.unpaidForPayer(studentId:payerType==_PayerType.student?studentId:null,familyId:payerType==_PayerType.family?familyId:null,includePaid:payerType==_PayerType.student);
      final credit = await repo.availableCredit(
        studentId: _payerType == _PayerType.student ? studentId : null,
        familyId: _payerType == _PayerType.family ? familyId : null,
      );
      if (!mounted || payerType != _payerType ||
          studentId != _studentId || familyId != _familyId) return;
      setState(() {
        _outstanding = value;
        _credit = credit;
        _payerDues = dues;
        _selectedDues.clear();
        if (payerType == _PayerType.family) {
          _selectedDues.addAll(dues.where((d) => d.balance > 0).map((d) => d.id));
        } else {
          final available = dues.where((d) => d.balance > 0).toList();
          _feeId = available.isNotEmpty ? available.first.feeId :
              (dues.isNotEmpty ? dues.first.feeId : null);
          for (final due in available) {
            if (due.feeId == _feeId) { _selectedDues.add(due.id); break; }
          }
        }
        _amount.text = _selectedRemaining > 0 ? _selectedRemaining.toString() : '';
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chargement impossible : ${FriendlyError.message(error)}')));
    } finally {
      if (mounted) setState(() => _loadingBalance = false);
    }
  }

  Future<void> _applyCredit() async {
    if (_credit <= 0 || _selectedDues.isEmpty) return;
    setState(() => _saving = true);
    try {
      final applied = await ref.read(financeRepositoryProvider).applyAvailableCredit(
            studentId: _payerType == _PayerType.student ? _studentId : null,
            familyId: _payerType == _PayerType.family ? _familyId : null,
            dueIds: _selectedDues.toList(),
          );
      ref.invalidate(dashboardProvider);
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(auditEntriesProvider);
      if (_payerType == _PayerType.family && _familyId != null) {
        ref.invalidate(familyBalanceProvider(_familyId!));
      }
      await _loadOutstanding();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Avoir appliqué : ${formatXaf(applied)}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final payerOk =
        _payerType == _PayerType.student ? _studentId != null : _familyId != null;
    if (!_formKey.currentState!.validate() || !payerOk) return;
    if (_selectedDues.isEmpty || _selectedRemaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez une rubrique et une période non soldée.')));
      return;
    }
    final requested = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (requested > _selectedRemaining) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le montant dépasse les périodes choisies. Sélectionnez aussi les autres périodes concernées.')));
      return;
    }
    final selectedLabels = _payerDues
        .where((d) => _selectedDues.contains(d.id))
        .map((d) => _periodLabel(d) + ' · ' + d.feeName).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer le paiement'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Montant reçu : ' + formatXaf(requested),
              style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Mode de paiement : ' + _method),
            const SizedBox(height: 10),
            const Text('Périodes sélectionnées :'),
            ...selectedLabels.map((label) => Text('• ' + label)),
            const SizedBox(height: 8),
            if (requested < _selectedRemaining)
              const Text('Versement partiel : le solde restera dû.'),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Corriger')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer et enregistrer')),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      final amount = int.parse(_amount.text.replaceAll(RegExp(r'\D'), ''));
      final repo = ref.read(financeRepositoryProvider);
      final String receipt;
      final String beneficiaryName;
      if (_payerType == _PayerType.student) {
        receipt = await repo.recordPayment(
          studentId: _studentId!,
          amount: amount,
          method: _method,
          note: _note.text, dueIds:_selectedDues.toList(), cashAccountId:_cashAccountId, transactionReference:_reference.text, payerPhone:_payerPhone.text, paymentOperator:_operator.text,
        );
        final students = await ref.read(studentsProvider.future);
        beneficiaryName = students.firstWhere((s) => s.id == _studentId).fullName;
      } else {
        receipt = await repo.recordFamilyPayment(
          familyId: _familyId!,
          amount: amount,
          method: _method,
          note: _note.text, dueIds:_selectedDues.toList(), cashAccountId:_cashAccountId, transactionReference:_reference.text, payerPhone:_payerPhone.text, paymentOperator:_operator.text,
        );
        final families = await ref.read(familiesProvider.future);
        beneficiaryName = families.firstWhere((f) => f.id == _familyId).name;
      }
      ref.invalidate(recentPaymentsProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(unpaidDuesProvider);
      ref.invalidate(auditEntriesProvider);
      if (_payerType == _PayerType.family) {
        ref.invalidate(familyBalanceProvider(_familyId!));
      }
      if (!mounted) return;
      final receiptPrefs = await ReceiptPrintingPreferencesStore().load();
      if (receiptPrefs.autoPrint && receiptPrefs.format.isPos) {
        await _printReceipt(
          receiptNumber: receipt,
          beneficiaryName: beneficiaryName,
          amount: amount,
          paidAt: DateTime.now(),
          format: receiptPrefs.format,
          directToPrinter: true,
          preferences: receiptPrefs,
        );
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paiement enregistré'),
          content: Text('Reçu $receipt créé avec succès pour $beneficiaryName.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await _printReceipt(
                  receiptNumber: receipt,
                  beneficiaryName: beneficiaryName,
                  amount: amount,
                  paidAt: DateTime.now(),
                  format: ReceiptFormat.a5,
                );
              },
              icon: const Icon(Icons.description_outlined),
              label: const Text('Reçu A5'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final prefs = await ReceiptPrintingPreferencesStore().load();
                final posFormat = prefs.format.isPos ? prefs.format : ReceiptFormat.pos80;
                await _printReceipt(
                  receiptNumber: receipt,
                  beneficiaryName: beneficiaryName,
                  amount: amount,
                  paidAt: DateTime.now(),
                  format: posFormat,
                  directToPrinter: true,
                  preferences: prefs,
                );
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimer POS'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyError.message(error),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printReceipt({
    required String receiptNumber,
    required String beneficiaryName,
    required int amount,
    required DateTime paidAt,
    ReceiptFormat format = ReceiptFormat.a5,
    bool directToPrinter = false,
    ReceiptPrintingPreferences? preferences,
  }) async {
    final establishment = await ref.read(establishmentProvider.future);
    final allocationRows = await ref.read(financeRepositoryProvider).paymentReceiptLines(receiptNumber);
    final lines = allocationRows
        .map((r) => ReceiptLine(
              label: '${r['fee_name']} · ${r['period_key']}',
              amount: r['amount'] as int,
            ))
        .toList();
    final prefs = preferences ?? await ReceiptPrintingPreferencesStore().load();
    final printer = ReceiptPrinter(ReceiptService());
    try {
      await printer.printReceipt(
        establishment: establishment,
        receiptNumber: receiptNumber,
        beneficiaryName: beneficiaryName,
        amount: amount,
        paymentMethod: _method,
        paidAt: paidAt,
        paymentReference: _reference.text.trim(),
        lines: lines,
        format: format,
        directToPrinter: directToPrinter,
        printerUrl: prefs.printerUrl,
        showLogo: format.isPos ? prefs.showLogo : true,
        includeDetails: format.isPos ? prefs.includeDetails : true,
        copies: format.isPos ? prefs.copies : 1,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Impossible d'imprimer le reçu : $error")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider);
    final families = ref.watch(familiesProvider);
    final cycles = ref.watch(cyclesProvider);
    final classrooms = ref.watch(classroomsProvider);
    final content = Form(
      key: _formKey,
      child: LayoutBuilder(builder: (context, viewport) {
        final desktopForm = WindowsUi.isDesktop(context) &&
            viewport.maxWidth >= 860;
        final selectors = <Widget>[
          if (desktopForm) ...[
            Text('Sélection du payeur',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
          ],
            SegmentedButton<_PayerType>(
              segments: const [
                ButtonSegment(
                  value: _PayerType.student,
                  label: Text('Élève'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: _PayerType.family,
                  label: Text('Famille'),
                  icon: Icon(Icons.family_restroom),
                ),
              ],
              selected: {_payerType},
              onSelectionChanged: (value) {
                setState(() {
                  _payerType = value.first;
                  _outstanding = null;
                  _amount.clear();
                });
                _loadOutstanding();
              },
            ),
            const SizedBox(height: 12),
            if (_payerType == _PayerType.student) ...[
              cycles.when(
                data: (items) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const ValueKey('payment_cycle'),
                  initialValue: items.any((c) => c['id'] == _cycleId) ? _cycleId : null,
                  decoration: const InputDecoration(
                    labelText: '1. Cycle *', prefixIcon: Icon(Icons.school_outlined)),
                  items: items.map((c) => DropdownMenuItem(
                    value: c['id'] as String, child: Text(c['name'] as String))).toList(),
                  onChanged: (cycle) {
                    setState(() {
                      _cycleId = cycle;
                      _classroomId = null;
                      _studentId = null;
                      _payerDues = const [];
                      _selectedDues.clear();
                      _feeId = null;
                      _outstanding = null;
                      _amount.clear();
                    });
                  },
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('$error'),
              ),
              const SizedBox(height: 12),
              if (_cycleId != null) classrooms.when(
                data: (items) {
                  final filtered = items.where((c) => c.cycleId == _cycleId).toList();
                  return DropdownButtonFormField<String>(
                  isExpanded: true,
                    key: ValueKey('payment_class_${_cycleId}'),
                    initialValue: filtered.any((c) => c.id == _classroomId)
                        ? _classroomId : null,
                    decoration: const InputDecoration(
                      labelText: '2. Classe / salle *',
                      prefixIcon: Icon(Icons.meeting_room_outlined)),
                    items: filtered.map((c) => DropdownMenuItem(
                      value: c.id, child: Text(c.name))).toList(),
                    onChanged: (id) {
                      setState(() {
                        _classroomId = id;
                        _studentId = null;
                        _payerDues = const [];
                        _selectedDues.clear();
                        _feeId = null;
                        _outstanding = null;
                        _amount.clear();
                      });
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('$error'),
              ),
              if (_classroomId != null) ...[
                const SizedBox(height: 12),
                students.when(
                  data: (items) => _StudentSearchField(
                    key: ValueKey('payment_student_${_cycleId}_${_classroomId}'),
                    students: items.where((s) =>
                      s.cycleId == _cycleId && s.classroomId == _classroomId).toList(),
                    selectedId: _studentId,
                    onSelected: (student) {
                      setState(() {
                        _studentId = student?.id;
                        _outstanding = null;
                        _amount.clear();
                        _payerDues = const [];
                        _selectedDues.clear();
                        _feeId = null;
                      });
                      _loadOutstanding();
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('$error'),
                ),
              ],
            ] else
              families.when(
                data: (items) => items.isEmpty
                    ? const Text(
                        'Aucune famille enregistrée. Créez-en une depuis Élèves > Familles.',
                      )
                    : _FamilySearchField(
                        families: items,
                        selectedId: _familyId,
                        onSelected: (family) {
                          setState(() {
                            _familyId = family?.id;
                            _outstanding = null;
                            _amount.clear();
                          });
                          _loadOutstanding();
                        },
                      ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('$error'),
              ),
        ];
        final checkout = <Widget>[
          if (desktopForm) ...[
            Text('Détails du règlement',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
          ],
            if (_loadingBalance)
              const LinearProgressIndicator()
            else if (_outstanding != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Reste à payer (toutes rubriques)'),
                  subtitle: Text(
                    _outstanding == 0
                        ? 'Aucune période impayée'
                        : 'Le versement concerne uniquement les périodes cochées.',
                  ),
                  trailing: Text(
                    formatXaf(_outstanding!),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: _selectedRemaining > 0
                      ? () => _amount.text = _selectedRemaining.toString()
                      : null,
                ),
              ),
            if (_credit > 0) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.savings_outlined),
                  title: const Text('Avoir disponible'),
                  subtitle: const Text('Utilisez cet avoir sur les périodes choisies sans nouvel encaissement.'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatXaf(_credit), style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextButton(
                        onPressed: _saving || _selectedDues.isEmpty ? null : _applyCredit,
                        child: const Text('Utiliser'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_payerType == _PayerType.student && _studentId != null &&
                !_loadingBalance && _payerDues.isEmpty)
              const Card(child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Aucun frais à payer'),
                subtitle: Text('Vérifiez que l’élève est inscrit dans l’année active '
                    'et qu’un tarif est défini pour son cycle ou sa classe.'))),
            if (_payerType == _PayerType.student && _payerDues.isNotEmpty) ...[
              Text('4. Rubrique à payer',
                style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                key: ValueKey('payment_fee_${_studentId}_${_payerDues.length}'),
                initialValue: _payerDues.any((d) => d.feeId == _feeId)
                    ? _feeId : null,
                decoration: const InputDecoration(
                  labelText: 'Rubrique', prefixIcon: Icon(Icons.category_outlined)),
                items: {
                  for (final due in _payerDues) due.feeId!: due.feeName,
                }.entries.map((entry) => DropdownMenuItem(
                  value: entry.key, child: Text(entry.value,
                    maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _saving ? null : _chooseRubric,
              ),
              if (_feeId != null) ...[
                const SizedBox(height: 12),
                Text('5. Sélectionner un ou plusieurs mois / trimestres',
                  style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final due in _payerDues.where((d) => d.feeId == _feeId))
                    ChoiceChip(
                      selected: _selectedDues.contains(due.id),
                      onSelected: due.balance <= 0 || _saving ? null
                          : (selected) => _chooseDue(due, selected),
                      tooltip: 'Tarif : ' + formatXaf(due.amountDue) +
                          ' · Déjà payé : ' + formatXaf(due.amountPaid) +
                          _periodDeadline(due),
                      label: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_periodLabel(due),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(due.balance <= 0 ? 'Soldé'
                          : due.amountPaid > 0 ? 'Partiel · ' + formatXaf(due.balance)
                          : 'À payer · ' + formatXaf(due.balance),
                          style: Theme.of(context).textTheme.labelSmall),
                      ]),
                    ),
                ]),
              ],
              Card(child: ListTile(
                title: const Text('Total des périodes sélectionnées'),
                trailing: Text(formatXaf(_selectedRemaining),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            ] else if (_payerType == _PayerType.family && _payerDues.isNotEmpty) ...[
              Text('Périodes à régler pour la famille',
                  style: Theme.of(context).textTheme.titleMedium),
              ..._payerDues.map((d) => CheckboxListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                value: _selectedDues.contains(d.id),
                title: Text('${d.studentName} · ${d.feeName} · ${d.periodKey}'),
                subtitle: Text('Reste ${formatXaf(d.balance)}'),
                onChanged: (v) => _chooseDueFamily(d, v == true),
              )),
            ],
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Montant (FCFA) *',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final amount = int.tryParse(
                  (value ?? '').replaceAll(RegExp(r'\D'), ''),
                );
                if (amount == null || amount <= 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),
            if (_loadingPaymentConfig)
              const LinearProgressIndicator()
            else ...[
              DropdownButtonFormField<String>(
                  isExpanded: true,
                initialValue: _paymentMethods.any((m) => m['name'] == _method) ? _method : null,
                decoration: const InputDecoration(
                  labelText: 'Mode de paiement',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: _paymentMethods
                    .map((m) => DropdownMenuItem(value: m['name'] as String, child: Text(m['name'] as String)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _method = value;
                    _cashAccountId = _compatibleAccountId(value, current: _cashAccountId);
                  });
                },
                validator: (value) => value == null ? 'Moyen de paiement obligatoire' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                initialValue: _cashAccounts.any((a) => a['id'] == _cashAccountId && a['type'] == _methodAccountType) ? _cashAccountId : null,
                decoration: const InputDecoration(labelText: 'Caisse / compte'),
                items: _cashAccounts
                    .where((a) => a['type'] == _methodAccountType)
                    .map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String)))
                    .toList(),
                onChanged: (value) => setState(() => _cashAccountId = value),
                validator: (value) => value == null ? 'Caisse / compte obligatoire' : null,
              ),
              const SizedBox(height: 12),
              if (_referenceRequired) ...[
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(labelText: 'Référence transaction *'),
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Référence obligatoire' : null,
                ),
                const SizedBox(height: 12),
              ],
              if (_methodAccountType == 'mobile') ...[
                TextFormField(controller: _operator, decoration: const InputDecoration(labelText: 'Opérateur (MTN, Airtel…)')),
                const SizedBox(height: 12),
                TextFormField(controller: _payerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro payeur')),
                const SizedBox(height: 12),
              ],
            ],
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 22),
            if (!desktopForm)
              FilledButton.icon(
                onPressed: _saving || _loadingBalance || _selectedDues.isEmpty ? null : _save,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Enregistrement…' : 'Valider le paiement'),
              ),
        ];
        if (!desktopForm) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [...selectors, const SizedBox(height: 12), ...checkout],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: WindowsPanel(
                padding: EdgeInsets.zero,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: selectors,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: WindowsPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: checkout,
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            const Expanded(child: Text('Périodes sélectionnées',
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Text(formatXaf(_selectedRemaining),
                              style: Theme.of(context).textTheme.titleMedium),
                          ]),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _saving || _loadingBalance ||
                                    _selectedDues.isEmpty ? null : _save,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(_saving
                                ? 'Enregistrement…' : 'Valider le paiement'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
    if (WindowsUi.isDesktop(context)) {
      return WindowsPageScaffold(
        title: 'Enregistrer un paiement',
        subtitle: 'Cycle, classe, élève, rubrique, période puis encaissement',
        maxWidth: 1460,
        body: content,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Enregistrer un paiement')),
      body: content,
    );
  }
}

/// Normalise une chaîne pour une recherche insensible à la casse et aux accents.
String _normalizeSearch(String value) {
  const from = 'àâäáãåèéêëìíîïòóôöõùúûüçñÀÂÄÁÃÅÈÉÊËÌÍÎÏÒÓÔÖÕÙÚÛÜÇÑ';
  const to = 'aaaaaaeeeeiiiiooooouuuucnAAAAAAEEEEIIIIOOOOOUUUUCN';
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}

/// Champ de recherche d'élève : remplace la liste déroulante classique par
/// un champ texte avec suggestions filtrées en direct (nom, matricule),
/// beaucoup plus rapide à utiliser lorsqu'il y a de nombreux élèves.
class _StudentSearchField extends StatefulWidget {
  const _StudentSearchField({
    super.key,
    required this.students,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Student> students;
  final String? selectedId;
  final ValueChanged<Student?> onSelected;

  @override
  State<_StudentSearchField> createState() => _StudentSearchFieldState();
}

class _StudentSearchFieldState extends State<_StudentSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  String _label(Student s) => '${s.fullName} · ${s.classroomName}';

  Student? _findById(String? id) {
    if (id == null) return null;
    for (final s in widget.students) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _label2(_findById(widget.selectedId)));
    _focusNode = FocusNode();
  }

  String _label2(Student? s) => s == null ? '' : _label(s);

  @override
  void didUpdateWidget(covariant _StudentSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId != oldWidget.selectedId) {
      final selected = _findById(widget.selectedId);
      if (selected == null) {
        _controller.clear();
      } else {
        _controller.text = _label(selected);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.selectedId,
      validator: (value) => value == null ? 'Élève obligatoire' : null,
      builder: (state) {
        if (state.value != widget.selectedId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) state.didChange(widget.selectedId);
          });
        }
        return RawAutocomplete<Student>(
          textEditingController: _controller,
          focusNode: _focusNode,
          displayStringForOption: _label,
          optionsBuilder: (value) {
            final query = _normalizeSearch(value.text.trim());
            if (query.isEmpty) return widget.students.take(40);
            return widget.students.where((s) {
              final haystack = _normalizeSearch('${s.fullName} ${s.classroomName} ${s.registrationNumber ?? ''}');
              return haystack.contains(query);
            }).take(40);
          },
          onSelected: (student) {
            state.didChange(student.id);
            widget.onSelected(student);
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'Élève *',
                hintText: 'Rechercher par nom ou matricule…',
                prefixIcon: const Icon(Icons.person_search_outlined),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          state.didChange(null);
                          widget.onSelected(null);
                        },
                      ),
                errorText: state.errorText,
              ),
              onChanged: (text) {
                if (state.value != null && text != _label2(_findById(state.value))) {
                  state.didChange(null);
                  widget.onSelected(null);
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280, minWidth: 280),
                  child: list.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucun élève trouvé'))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final s = list[index];
                            return ListTile(
                              dense: true,
                              title: Text(s.fullName),
                              subtitle: Text(
                                '${s.classroomName}${s.registrationNumber != null && s.registrationNumber!.isNotEmpty ? ' · ${s.registrationNumber}' : ''}',
                              ),
                              onTap: () => onSelected(s),
                            );
                          },
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Champ de recherche de famille, même principe que [_StudentSearchField].
class _FamilySearchField extends StatefulWidget {
  const _FamilySearchField({
    required this.families,
    required this.selectedId,
    required this.onSelected,
  });

  final List<FamilyItem> families;
  final String? selectedId;
  final ValueChanged<FamilyItem?> onSelected;

  @override
  State<_FamilySearchField> createState() => _FamilySearchFieldState();
}

class _FamilySearchFieldState extends State<_FamilySearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  String _label(FamilyItem f) => '${f.name} (${f.studentCount} élève(s))';

  FamilyItem? _findById(String? id) {
    if (id == null) return null;
    for (final f in widget.families) {
      if (f.id == id) return f;
    }
    return null;
  }

  String _label2(FamilyItem? f) => f == null ? '' : _label(f);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _label2(_findById(widget.selectedId)));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _FamilySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId != oldWidget.selectedId) {
      final selected = _findById(widget.selectedId);
      if (selected == null) {
        _controller.clear();
      } else {
        _controller.text = _label(selected);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: widget.selectedId,
      validator: (value) => value == null ? 'Famille obligatoire' : null,
      builder: (state) {
        if (state.value != widget.selectedId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) state.didChange(widget.selectedId);
          });
        }
        return RawAutocomplete<FamilyItem>(
          textEditingController: _controller,
          focusNode: _focusNode,
          displayStringForOption: _label,
          optionsBuilder: (value) {
            final query = _normalizeSearch(value.text.trim());
            if (query.isEmpty) return widget.families.take(40);
            return widget.families.where((f) {
              final haystack = _normalizeSearch('${f.name} ${f.primaryPhone ?? ''} ${f.secondaryPhone ?? ''}');
              return haystack.contains(query);
            }).take(40);
          },
          onSelected: (family) {
            state.didChange(family.id);
            widget.onSelected(family);
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'Famille *',
                hintText: 'Rechercher par nom ou téléphone…',
                prefixIcon: const Icon(Icons.family_restroom),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          state.didChange(null);
                          widget.onSelected(null);
                        },
                      ),
                errorText: state.errorText,
              ),
              onChanged: (text) {
                if (state.value != null && text != _label2(_findById(state.value))) {
                  state.didChange(null);
                  widget.onSelected(null);
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280, minWidth: 280),
                  child: list.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('Aucune famille trouvée'))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final f = list[index];
                            return ListTile(
                              dense: true,
                              title: Text(f.name),
                              subtitle: Text('${f.studentCount} élève(s)${f.primaryPhone != null && f.primaryPhone!.isNotEmpty ? ' · ${f.primaryPhone}' : ''}'),
                              onTap: () => onSelected(f),
                            );
                          },
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
