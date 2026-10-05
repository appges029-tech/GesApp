import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/layout/responsive_layout.dart';

import '../../core/platform/download_service.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/hr.dart';
import '../../services/payroll_pdf_service.dart';
import '../../services/document_number_service.dart';
import '../../services/document_identity.dart';

class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  int _refresh = 0;

  void _reload() => setState(() => _refresh++);

  Future<void> _createPeriod() async {
    final now = DateTime.now();
    var start = DateTime(now.year, now.month, 1);
    var end = DateTime(now.year, now.month + 1, 0);
    final label = TextEditingController(
      text: 'Paie ${DateFormat('MMMM yyyy', 'fr_FR').format(now)}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nouvelle période de paie'),
          content: ResponsiveDialogContent(maxWidth: 460, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Libellé'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Début'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => start = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fin'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(end)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: end.isBefore(start) ? start : end,
                      firstDate: start,
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => end = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: label.text.trim().isEmpty || end.isBefore(start)
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Calculer'),
            ),
          ],
        ),
      ),
    );

    try {
      if (ok == true) {
        await ref.read(hrRepositoryProvider).createPayrollPeriod(
              label: label.text.trim(),
              startDate: start,
              endDate: end,
            );
        if (mounted) {
          _reload();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      label.dispose();
    }
  }

  String? _firstCompatibleAccount(
    List<Map<String, Object?>> accounts,
    List<Map<String, Object?>> methods,
    String methodName,
  ) {
    Map<String, Object?>? method;
    for (final item in methods) {
      if (item['name']?.toString() == methodName) {
        method = item;
        break;
      }
    }
    final expectedType = method?['account_type']?.toString();
    for (final account in accounts) {
      if (expectedType == null || account['type']?.toString() == expectedType) {
        return account['id']?.toString();
      }
    }
    return accounts.isEmpty ? null : accounts.first['id']?.toString();
  }

  Future<void> _grantAdvance() async {
    final repository = ref.read(hrRepositoryProvider);
    final employees = await repository.employees(status: 'active', limit: 500);
    final methods = await ref.read(financeRepositoryProvider).paymentMethods();
    final accounts = await ref.read(cashRepositoryProvider).accounts();

    if (!mounted) return;
    if (employees.isEmpty || methods.isEmpty || accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un employé, un moyen de paiement et un compte.'),
        ),
      );
      return;
    }

    var employeeId = employees.first.id;
    var methodName = methods.first['name'].toString();
    var accountId = _firstCompatibleAccount(accounts, methods, methodName) ??
        accounts.first['id'].toString();
    final amount = TextEditingController();
    final reference = TextEditingController();
    final note = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Avance sur salaire'),
          content: ResponsiveDialogContent(maxWidth: 520, child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: employeeId,
                    decoration: const InputDecoration(labelText: 'Employé'),
                    items: employees
                        .map(
                          (employee) => DropdownMenuItem(
                            value: employee.id,
                            child: Text(employee.fullName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => employeeId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Montant XAF'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: methodName,
                    decoration: const InputDecoration(labelText: 'Moyen de paiement'),
                    items: methods
                        .map(
                          (method) => DropdownMenuItem(
                            value: method['name'].toString(),
                            child: Text(method['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        methodName = value;
                        accountId = _firstCompatibleAccount(
                              accounts,
                              methods,
                              methodName,
                            ) ??
                            accountId;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('$methodName-$accountId'),
                    initialValue: accountId,
                    decoration: const InputDecoration(labelText: 'Caisse / compte'),
                    items: accounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account['id'].toString(),
                            child: Text(account['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => accountId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(labelText: 'Référence'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Décaisser'),
            ),
          ],
        ),
      ),
    );

    try {
      if (ok == true) {
        await repository.grantAdvance(
          employeeId: employeeId,
          amount: int.tryParse(amount.text.replaceAll(' ', '')) ?? 0,
          paymentMethod: methodName,
          cashAccountId: accountId,
          reference: reference.text.trim(),
          note: note.text.trim(),
        );
        if (mounted) {
          _reload();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      amount.dispose();
      reference.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paie'),
        actions: [
          IconButton(
            tooltip: 'Avance sur salaire',
            icon: const Icon(Icons.payments_outlined),
            onPressed: _grantAdvance,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPeriod,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Calculer une paie'),
      ),
      body: FutureBuilder<List<PayrollPeriodItem>>(
        key: ValueKey(_refresh),
        future: ref.read(hrRepositoryProvider).payrollPeriods(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final periods = snapshot.data!;
          if (periods.isEmpty) {
            return const Center(child: Text('Aucune période de paie.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: periods.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final period = periods[index];
              return Card(
                child: ListTile(
                  title: Text(
                    period.label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${period.entryCount} employés · Net ${formatXaf(period.totalNet)} · ${period.status}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PayrollPeriodScreen(period: period),
                      ),
                    );
                    if (mounted) _reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PayrollPeriodScreen extends ConsumerStatefulWidget {
  const PayrollPeriodScreen({super.key, required this.period});

  final PayrollPeriodItem period;

  @override
  ConsumerState<PayrollPeriodScreen> createState() => _PayrollPeriodScreenState();
}

class _PayrollPeriodScreenState extends ConsumerState<PayrollPeriodScreen> {
  int _refresh = 0;

  void _reload() => setState(() => _refresh++);

  String? _firstCompatibleAccount(
    List<Map<String, Object?>> accounts,
    List<Map<String, Object?>> methods,
    String methodName,
  ) {
    Map<String, Object?>? method;
    for (final item in methods) {
      if (item['name']?.toString() == methodName) {
        method = item;
        break;
      }
    }
    final expectedType = method?['account_type']?.toString();
    for (final account in accounts) {
      if (expectedType == null || account['type']?.toString() == expectedType) {
        return account['id']?.toString();
      }
    }
    return accounts.isEmpty ? null : accounts.first['id']?.toString();
  }

  Future<void> _pay(PayrollEntryItem entry) async {
    final methods = await ref.read(financeRepositoryProvider).paymentMethods();
    final accounts = await ref.read(cashRepositoryProvider).accounts();
    if (!mounted) return;
    if (methods.isEmpty || accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun moyen de paiement ou compte disponible.')),
      );
      return;
    }

    var methodName = methods.first['name'].toString();
    var accountId = _firstCompatibleAccount(accounts, methods, methodName) ??
        accounts.first['id'].toString();
    final reference = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Payer ${entry.employeeName}'),
          content: ResponsiveDialogContent(maxWidth: 480, child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Net à payer : ${formatXaf(entry.netSalary)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: methodName,
                  decoration: const InputDecoration(labelText: 'Moyen de paiement'),
                  items: methods
                      .map(
                        (method) => DropdownMenuItem(
                          value: method['name'].toString(),
                          child: Text(method['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      methodName = value;
                      accountId = _firstCompatibleAccount(
                            accounts,
                            methods,
                            methodName,
                          ) ??
                          accountId;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('$methodName-$accountId'),
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Compte / caisse'),
                  items: accounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account['id'].toString(),
                          child: Text(account['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => accountId = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Référence'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Payer'),
            ),
          ],
        ),
      ),
    );

    try {
      if (ok == true) {
        await ref.read(hrRepositoryProvider).payPayrollEntry(
              entryId: entry.id,
              paymentMethod: methodName,
              cashAccountId: accountId,
              reference: reference.text.trim(),
            );
        ref.invalidate(dashboardProvider);
        if (mounted) _reload();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      reference.dispose();
    }
  }

  Future<void> _payslip(PayrollEntryItem entry) async {
    final repo = ref.read(hrRepositoryProvider);
    final items = await repo.payrollItems(entry.id);
    final employee = await repo.employee(entry.employeeId);
    final establishment = await ref.read(settingsRepositoryProvider).establishment();
    final identity = await DocumentIdentity.fromEstablishment(establishment);
    final registry = DocumentNumberService();
    final reference = await registry.getOrCreate(type: 'BP', entityId: entry.id);
    final bytes = await PayrollPdfService().payslip(
      entry: entry,
      periodLabel: widget.period.label,
      items: items,
      identity: identity,
      reference: reference,
      employeeNumber: employee?.employeeNumber ?? '',
      position: employee?.positionName ?? '',
      department: employee?.departmentName ?? '',
    );
    await registry.recordFingerprint(reference: reference, bytes: bytes);
    await downloadBytes(
      bytes: bytes,
      fileName: 'Bulletin_${entry.employeeName.replaceAll(' ', '_')}_$reference.pdf',
      mimeType: 'application/pdf',
    );
  }

  Future<void> _validatePeriod() async {
    try {
      await ref.read(hrRepositoryProvider).validatePayrollPeriod(widget.period.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PayrollEntryItem>>(
      key: ValueKey(_refresh),
      future: ref.read(hrRepositoryProvider).payrollEntries(widget.period.id),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <PayrollEntryItem>[];
        final hasDraft = entries.any((entry) => entry.status == 'draft');

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.period.label),
            actions: [
              if (hasDraft)
                TextButton.icon(
                  onPressed: _validatePeriod,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Valider'),
                ),
            ],
          ),
          body: !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
                  ? const Center(child: Text('Aucun employé calculé pour cette période.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return Card(
                          child: ListTile(
                            title: Text(
                              entry.employeeName,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Base ${formatXaf(entry.baseSalary)} · Brut ${formatXaf(entry.grossSalary)} · '
                              'Retenues ${formatXaf(entry.totalDeductions)}\n'
                              'Net ${formatXaf(entry.netSalary)} · ${entry.status}',
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'pay') {
                                  await _pay(entry);
                                } else if (value == 'pdf') {
                                  await _payslip(entry);
                                }
                              },
                              itemBuilder: (_) => [
                                if (entry.status == 'validated')
                                  const PopupMenuItem(
                                    value: 'pay',
                                    child: Text('Payer'),
                                  ),
                                const PopupMenuItem(
                                  value: 'pdf',
                                  child: Text('Bulletin PDF'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
